// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { StrategyUtils } from "src/strategy/libs/StrategyUtils.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";

library PriceReturn {
    function calculateWeightedPriceReturn(
        int256 priceReturn,
        uint256 reserveValue,
        ILMPStrategy.RebalanceDirection direction
    ) external view returns (int256) {
        ILMPStrategy strategy = ILMPStrategy(address(this));

        // slither-disable-next-line timestamp
        if (priceReturn > 0) {
            // LST trading at a discount
            if (direction == ILMPStrategy.RebalanceDirection.Out) {
                return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPriceDiscountExit()
                    / 1e6;
            } else {
                return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPriceDiscountEnter()
                    / 1e6;
            }
        } else {
            // LST trading at 0 or a premium
            return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPricePremium() / 1e6;
        }
    }

    function calculatePriceReturns(IDexLSTStats.DexLSTStatsData memory stats) external view returns (int256[] memory) {
        ILMPStrategy strategy = ILMPStrategy(address(this));

        ILSTStats.LSTStatsData[] memory lstStatsData = stats.lstStatsData;

        uint256 numLsts = lstStatsData.length;
        int256[] memory priceReturns = new int256[](numLsts);

        for (uint256 i = 0; i < numLsts; ++i) {
            ILSTStats.LSTStatsData memory data = lstStatsData[i];

            uint256 scalingFactor = 1e18; // default scalingFactor is 1

            int256 discount = data.discount;
            if (discount > strategy.maxAllowedDiscount()) {
                discount = strategy.maxAllowedDiscount();
            }

            // discount value that is negative indicates LST price premium
            // scalingFactor = 1e18 for premiums and discounts that are small
            // discountTimestampByPercent array holds the timestamp in position i for discount = (i+1)%
            uint40[5] memory discountTimestampByPercent = data.discountTimestampByPercent;

            // 1e16 means a 1% LST discount where full scale is 1e18.
            if (discount > 1e16) {
                // linear approximation for exponential function with approx. half life of 30 days
                uint256 halfLifeSec = 30 * 24 * 60 * 60;
                uint256 len = data.discountTimestampByPercent.length;
                for (uint256 j = 1; j < len; ++j) {
                    // slither-disable-next-line timestamp
                    if (discount <= StrategyUtils.convertUintToInt((j + 1) * 1e16)) {
                        // current timestamp should be strictly >= timestamp in discountTimestampByPercent
                        uint256 timeSinceDiscountSec =
                            uint256(uint40(block.timestamp) - discountTimestampByPercent[j - 1]);
                        scalingFactor >>= (timeSinceDiscountSec / halfLifeSec);
                        // slither-disable-next-line weak-prng
                        timeSinceDiscountSec %= halfLifeSec;
                        scalingFactor -= scalingFactor * timeSinceDiscountSec / halfLifeSec / 2;
                        break;
                    }
                }
            }
            priceReturns[i] = discount * StrategyUtils.convertUintToInt(scalingFactor) / 1e18;
        }

        return priceReturns;
    }
}
