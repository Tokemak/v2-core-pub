// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string,state-visibility,max-line-length,gas-custom-errors

import { Systems } from "script/utils/Constants.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { ILMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";

/**
 * @dev This contract:
 *      1. Deploys a new LMP strategy template with the following configuration.
 *      2. Registers the new strategy template in the `lst-guarded-r1` LMP Vault Factory.
 */
contract CreateLMPStrategy is BaseScript {
    // 🚨 Manually set variables below. 🚨
    bytes32 public lmpVaultType = keccak256("lst-guarded-r1");

    LMPStrategyConfig.StrategyConfig config = LMPStrategyConfig.StrategyConfig({
        swapCostOffset: LMPStrategyConfig.SwapCostOffsetConfig({
            initInDays: 60,
            tightenThresholdInViolations: 5,
            tightenStepInDays: 2,
            relaxThresholdInDays: 30,
            relaxStepInDays: 1,
            maxInDays: 60,
            minInDays: 7
        }),
        navLookback: LMPStrategyConfig.NavLookbackConfig({ lookback1InDays: 30, lookback2InDays: 60, lookback3InDays: 90 }),
        slippage: LMPStrategyConfig.SlippageConfig({
            maxNormalOperationSlippage: 5e15, // 0.5%
            maxTrimOperationSlippage: 2e16, // 2%
            maxEmergencyOperationSlippage: 0.025e18, // 2.5%
            maxShutdownOperationSlippage: 0.015e18 // 1.5%
         }),
        modelWeights: LMPStrategyConfig.ModelWeights({
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

        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, config);
        ILMPVaultFactory lmpFactory = systemRegistry.getLMPVaultFactoryByType(lmpVaultType);

        if (address(lmpFactory) == address(0)) {
            revert("LMP Vault Factory not set for lst-guarded-r1 type");
        }

        lmpFactory.addStrategyTemplate(address(stratTemplate));
        console.log("LMP Strategy address: %s", address(stratTemplate));

        vm.stopBroadcast();
    }
}
