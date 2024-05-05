// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string,state-visibility,max-line-length,gas-custom-errors

import { Systems } from "script/utils/Constants.sol";
import { AutoPoolETHStrategy } from "src/strategy/AutoPoolETHStrategy.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { IAutoPoolFactory } from "src/vault/AutoPoolFactory.sol";
import { AutoPoolETHStrategyConfig } from "src/strategy/AutoPoolETHStrategyConfig.sol";

/**
 * @dev This contract:
 *      1. Deploys a new AutoPool strategy template with the following configuration.
 *      2. Registers the new strategy template in the `lst-guarded-r1` AutoPool Vault Factory.
 */
contract CreateAutoPoolETHStrategy is BaseScript {
    // 🚨 Manually set variables below. 🚨
    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    AutoPoolETHStrategyConfig.StrategyConfig config = AutoPoolETHStrategyConfig.StrategyConfig({
        swapCostOffset: AutoPoolETHStrategyConfig.SwapCostOffsetConfig({
            initInDays: 60,
            tightenThresholdInViolations: 5,
            tightenStepInDays: 2,
            relaxThresholdInDays: 30,
            relaxStepInDays: 1,
            maxInDays: 60,
            minInDays: 7
        }),
        navLookback: AutoPoolETHStrategyConfig.NavLookbackConfig({
            lookback1InDays: 30,
            lookback2InDays: 60,
            lookback3InDays: 90
        }),
        slippage: AutoPoolETHStrategyConfig.SlippageConfig({
            maxNormalOperationSlippage: 5e15, // 0.5%
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
        maxAllowedDiscount: 0.05e18, // 5%
        lstPriceGapTolerance: 5 // 5 bps
     });

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        AutoPoolETHStrategy stratTemplate = new AutoPoolETHStrategy(systemRegistry, config);
        IAutoPoolFactory autoPoolFactory = systemRegistry.getAutoPoolFactoryByType(autoPoolType);

        if (address(autoPoolFactory) == address(0)) {
            revert("AutoPool Vault Factory not set for lst-guarded-r1 type");
        }

        autoPoolFactory.addStrategyTemplate(address(stratTemplate));
        console.log("AutoPool Strategy address: %s", address(stratTemplate));

        vm.stopBroadcast();
    }
}
