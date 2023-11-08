// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { NavTracking } from "src/strategy/NavTracking.sol";
import { Errors } from "src/utils/Errors.sol";

library LMPStrategyConfig {
    error InvalidConfig(string paramName);

    // TODO: switch swapCostOffset from days to seconds; possibly pauseRebalance too
    struct StrategyConfig {
        SwapCostOffsetConfig swapCostOffset;
        NavLookbackConfig navLookback;
        SlippageConfig slippage;
        ModelWeights modelWeights;
        // number of days to pause rebalancing if a long-term nav decay is detected
        uint16 pauseRebalancePeriodInDays;
        // destinations trading a premium above maxPremium will be blocked from new capital deployments
        int256 maxPremium; // 100% = 1e18
        // destinations trading a discount above maxDiscount will be blocked from new capital deployments
        int256 maxDiscount; // 100% = 1e18
        // if any stats data is older than this, rebalancing will revert
        uint40 staleDataToleranceInSeconds;
        // the maximum discount incorporated in price return
        int256 maxAllowedDiscount;
        // the maximum deviation between spot & safe price for individual LSTs
        uint256 lstPriceGapTolerance;
    }

    struct SwapCostOffsetConfig {
        // the swap cost offset period to initialize the strategy with
        uint16 initInDays;
        // the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
        uint16 tightenThresholdInViolations;
        // the number of days to decrease the swap offset period for each tightening step
        uint16 tightenStepInDays;
        // the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
        uint16 relaxThresholdInDays;
        // the number of days to increase the swap offset period for each relaxing step
        uint16 relaxStepInDays;
        // the maximum the swap cost offset period can reach. This is the loosest the strategy will be
        uint16 maxInDays;
        // the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
        uint16 minInDays;
    }

    struct NavLookbackConfig {
        // the number of days for the first NAV decay comparison (e.g., 30 days)
        uint8 lookback1InDays;
        // the number of days for the second NAV decay comparison (e.g., 60 days)
        uint8 lookback2InDays;
        // the number of days for the third NAV decay comparison (e.g., 90 days)
        uint8 lookback3InDays;
    }

    struct SlippageConfig {
        // the maximum slippage that is allowed for a normal rebalance
        // under normal circumstances this will not be triggered because the swap offset logic is the primary gate
        // but this ensures a sensible slippage level will never be exceeded
        uint256 maxNormalOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
        // recommend setting this higher than maxNormalOperationSlippage
        uint256 maxTrimOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when a destinationVault has been shutdown
        // shutdown for a vault is abnormal and means there is an issue at that destination
        // recommend setting this higher than maxNormalOperationSlippage
        uint256 maxEmergencyOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when the LMPVault has been shutdown
        // TODO: why would a LMP be shutdown??
        uint256 maxShutdownOperationSlippage; // 100% = 1e18
    }

    struct ModelWeights {
        uint256 baseYield;
        uint256 feeYield;
        uint256 incentiveYield;
        uint256 slashing;
        int256 priceDiscountExit;
        int256 priceDiscountEnter;
        int256 pricePremium;
    }

    function validate(StrategyConfig memory config) internal pure {
        if (
            config.swapCostOffset.initInDays < config.swapCostOffset.minInDays
                || config.swapCostOffset.initInDays > config.swapCostOffset.maxInDays
        ) revert InvalidConfig("swapCostOffsetPeriodInit");

        if (config.swapCostOffset.maxInDays <= config.swapCostOffset.minInDays) {
            revert InvalidConfig("swapCostOffsetPeriodMax");
        }

        // the 91st spot holds current (0 days ago), so the farthest back that can be retrieved is 90 days ago
        if (
            config.navLookback.lookback1InDays >= NavTracking.MAX_NAV_TRACKING
                || config.navLookback.lookback2InDays >= NavTracking.MAX_NAV_TRACKING
                || config.navLookback.lookback3InDays > NavTracking.MAX_NAV_TRACKING
        ) {
            revert InvalidConfig("navLookbackInDays");
        }

        // lookback should be configured smallest to largest and should not be equal
        if (
            config.navLookback.lookback1InDays >= config.navLookback.lookback2InDays
                || config.navLookback.lookback2InDays >= config.navLookback.lookback3InDays
        ) {
            revert InvalidConfig("navLookbackInDays");
        }

        if (config.maxDiscount > 1e18) {
            revert InvalidConfig("maxDiscount");
        }

        if (config.maxPremium > 1e18) {
            revert InvalidConfig("maxPremium");
        }

        // TODO: these will revert with a different error, possibly confusing
        Errors.verifyNotZero(config.slippage.maxShutdownOperationSlippage, "maxShutdownOperationSlippage");
        Errors.verifyNotZero(config.slippage.maxEmergencyOperationSlippage, "maxEmergencyOperationSlippage");
        Errors.verifyNotZero(config.slippage.maxTrimOperationSlippage, "maxTrimOperationSlippage");
        Errors.verifyNotZero(config.slippage.maxNormalOperationSlippage, "maxNormalOperationSlippage");
        Errors.verifyNotZero(config.navLookback.lookback1InDays, "navLookback1");
    }
}
