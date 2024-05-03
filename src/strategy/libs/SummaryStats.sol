// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { StrategyUtils } from "src/strategy/libs/StrategyUtils.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { Incentives } from "src/strategy/libs/Incentives.sol";
import { PriceReturn } from "src/strategy/libs/PriceReturn.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

library SummaryStats {
    error StaleData(string name);
    error LstStatsReservesMismatch();

    event InLSTPriceGap(address token, uint256 priceSafe, uint256 priceSpot);
    event OutLSTPriceGap(address token, uint256 priceSafe, uint256 priceSpot);

    struct InterimStats {
        uint256 baseApr;
        int256 priceReturn;
        int256 maxDiscount;
        int256 maxPremium;
        uint256 reservesTotal;
        int256[] priceReturns;
        uint256 numLstStats;
    }

    function getDestinationSummaryStats(
        ILMPVault autoPool,
        IIncentivesPricingStats incentivePricing,
        address destAddress,
        uint256 price,
        ILMPStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory) {
        // NOTE: creating this as empty to save on variables later
        // has the distinct downside that if you forget to update a value, you get the zero value
        // slither-disable-next-line uninitialized-local
        IStrategy.SummaryStats memory result;

        if (destAddress == address(autoPool)) {
            result.destination = destAddress;
            result.ownedShares = autoPool.getAssetBreakdown().totalIdle;
            result.pricePerShare = price;
            return result;
        }

        IDestinationVault dest = IDestinationVault(destAddress);
        IDexLSTStats.DexLSTStatsData memory stats = dest.getStats().current();

        ensureNotStaleData("DexStats", stats.lastSnapshotTimestamp);

        // temporary holder to reduce variables
        InterimStats memory interimStats;

        interimStats.numLstStats = stats.lstStatsData.length;
        if (interimStats.numLstStats != stats.reservesInEth.length) revert LstStatsReservesMismatch();

        interimStats.priceReturns = PriceReturn.calculatePriceReturns(stats);

        for (uint256 i = 0; i < interimStats.numLstStats; ++i) {
            uint256 reserveValue = stats.reservesInEth[i];
            interimStats.reservesTotal += reserveValue;

            if (interimStats.priceReturns[i] != 0) {
                interimStats.priceReturn +=
                    PriceReturn.calculateWeightedPriceReturn(interimStats.priceReturns[i], reserveValue, direction);
            }

            // For tokens like WETH/ETH who have no data, tokens we've configured as NO_OP's in the
            // destinations/calculators, we can just skip the rest of these calcs as they have no stats
            if (stats.lstStatsData[i].baseApr == 0 && stats.lstStatsData[i].lastSnapshotTimestamp == 0) {
                continue;
            }

            ensureNotStaleData("lstData", stats.lstStatsData[i].lastSnapshotTimestamp);

            interimStats.baseApr += stats.lstStatsData[i].baseApr * reserveValue;

            int256 discount = stats.lstStatsData[i].discount;
            // slither-disable-next-line timestamp
            if (discount < interimStats.maxPremium) {
                interimStats.maxPremium = discount;
            }
            // slither-disable-next-line timestamp
            if (discount > interimStats.maxDiscount) {
                interimStats.maxDiscount = discount;
            }
        }

        // if reserves are 0, then leave baseApr + priceReturn as 0
        if (interimStats.reservesTotal > 0) {
            result.baseApr = interimStats.baseApr / interimStats.reservesTotal;
            result.priceReturn = interimStats.priceReturn / StrategyUtils.convertUintToInt(interimStats.reservesTotal);
        }

        result.destination = destAddress;
        result.feeApr = stats.feeApr;
        result.incentiveApr = Incentives.calculateIncentiveApr(
            incentivePricing, stats.stakingIncentiveStats, direction, destAddress, amount, price
        );
        result.safeTotalSupply = stats.stakingIncentiveStats.safeTotalSupply;
        result.ownedShares = dest.balanceOf(address(autoPool));
        result.pricePerShare = price;
        result.maxPremium = interimStats.maxPremium;
        result.maxDiscount = interimStats.maxDiscount;

        uint256 returnExPrice = (
            result.baseApr * ILMPStrategy(address(this)).weightBase() / 1e6
                + result.feeApr * ILMPStrategy(address(this)).weightFee() / 1e6
                + result.incentiveApr * ILMPStrategy(address(this)).weightIncentive() / 1e6
        );

        // price already weighted
        result.compositeReturn = StrategyUtils.convertUintToInt(returnExPrice) + result.priceReturn;

        return result;
    }

    // Calculate the largest difference between spot & safe price for the underlying LST tokens.
    // This does not support Curve meta pools
    function verifyLSTPriceGap(
        ILMPVault autoPool,
        IStrategy.RebalanceParams memory params,
        uint256 tolerance
    ) external returns (bool) {
        // Pricer
        ISystemRegistry registry = ISystemRegistry(ISystemComponent(address(this)).getSystemRegistry());
        IRootPriceOracle pricer = registry.rootPriceOracle();

        IDestinationVault dest;
        address[] memory lstTokens;
        uint256 numLsts;
        address dvPoolAddress;

        // Out Destination
        if (params.destinationOut != address(autoPool)) {
            dest = IDestinationVault(params.destinationOut);
            lstTokens = dest.underlyingTokens();
            numLsts = lstTokens.length;
            dvPoolAddress = dest.getPool();
            for (uint256 i = 0; i < numLsts; ++i) {
                uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
                uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], dvPoolAddress);
                // slither-disable-next-line reentrancy-events
                emit OutLSTPriceGap(lstTokens[i], priceSafe, priceSpot);
                // For out destination, the pool tokens should not be lower than safe price by tolerance
                if ((priceSafe == 0) || (priceSpot == 0)) {
                    return false;
                } else if (priceSafe > priceSpot) {
                    if (((priceSafe * 1.0e18 / priceSpot - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                        return false;
                    }
                }
            }
        }

        // In Destination
        dest = IDestinationVault(params.destinationIn);
        lstTokens = dest.underlyingTokens();
        numLsts = lstTokens.length;
        dvPoolAddress = dest.getPool();
        for (uint256 i = 0; i < numLsts; ++i) {
            uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
            uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], dvPoolAddress);
            // slither-disable-next-line reentrancy-events
            emit InLSTPriceGap(lstTokens[i], priceSafe, priceSpot);
            // For in destination, the pool tokens should not be higher than safe price by tolerance
            if ((priceSafe == 0) || (priceSpot == 0)) {
                return false;
            } else if (priceSpot > priceSafe) {
                if (((priceSpot * 1.0e18 / priceSafe - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                    return false;
                }
            }
        }

        return true;
    }

    function ensureNotStaleData(string memory name, uint256 dataTimestamp) internal view {
        // slither-disable-next-line timestamp
        if (block.timestamp - dataTimestamp > ILMPStrategy(address(this)).staleDataToleranceInSeconds()) {
            revert StaleData(name);
        }
    }
}
