// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { AutoPoolETHStrategyConfig } from "src/strategy/AutoPoolETHStrategyConfig.sol";

library AutoPoolETHStrategyTestHelpers {
    function getDefaultConfig() internal pure returns (AutoPoolETHStrategyConfig.StrategyConfig memory) {
        return AutoPoolETHStrategyConfig.StrategyConfig({
            swapCostOffset: AutoPoolETHStrategyConfig.SwapCostOffsetConfig({
                initInDays: 28,
                tightenThresholdInViolations: 5,
                tightenStepInDays: 3,
                relaxThresholdInDays: 20,
                relaxStepInDays: 3,
                maxInDays: 60,
                minInDays: 10
            }),
            navLookback: AutoPoolETHStrategyConfig.NavLookbackConfig({
                lookback1InDays: 30,
                lookback2InDays: 60,
                lookback3InDays: 90
            }),
            slippage: AutoPoolETHStrategyConfig.SlippageConfig({
                maxNormalOperationSlippage: 1e16, // 1%
                maxTrimOperationSlippage: 2e16, // 2%
                maxEmergencyOperationSlippage: 0.025e18, // 2.5%
                maxShutdownOperationSlippage: 0.015e18 // 1.5%
             }),
            modelWeights: AutoPoolETHStrategyConfig.ModelWeights({
                baseYield: 1e6,
                feeYield: 1e6,
                incentiveYield: 0.9e6,
                slashing: 1e6,
                priceDiscountExit: 0.75e6,
                priceDiscountEnter: 0,
                pricePremium: 1e6
            }),
            pauseRebalancePeriodInDays: 90,
            rebalanceTimeGapInSeconds: 28_800, // 8 hours
            maxPremium: 0.01e18, // 1%
            maxDiscount: 0.02e18, // 2%
            staleDataToleranceInSeconds: 2 days,
            maxAllowedDiscount: 0.05e18,
            lstPriceGapTolerance: 10 // 10 bps
         });
    }
}
