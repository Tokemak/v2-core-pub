// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { LMPVaultFactory, ILMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";

/**
 * @dev This contract:
 *      1. Deploys a new LMP strategy template with the following configuration.
 *      2. Registers the new strategy template in the `weth-vault` LMP Vault Factory.
 */
contract CreateLMPStrategy is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public lmp1SupplyLimit = type(uint112).max;
    uint256 public lmp1WalletLimit = type(uint112).max;
    string public lmp1SymbolSuffix = "EST";
    string public lmp1DescPrefix = "Established";
    bytes32 public lmpVaultType = keccak256("weth-vault");

    LMPStrategyConfig.StrategyConfig config = LMPStrategyConfig.StrategyConfig({
        swapCostOffset: LMPStrategyConfig.SwapCostOffsetConfig({
            initInDays: 28,
            tightenThresholdInViolations: 5,
            tightenStepInDays: 3,
            relaxThresholdInDays: 20,
            relaxStepInDays: 3,
            maxInDays: 60,
            minInDays: 10
        }),
        navLookback: LMPStrategyConfig.NavLookbackConfig({ lookback1InDays: 30, lookback2InDays: 60, lookback3InDays: 90 }),
        slippage: LMPStrategyConfig.SlippageConfig({
            maxNormalOperationSlippage: 1e16, // 1%
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
        maxPremium: 0.01e18, // 1%
        maxDiscount: 0.02e18, // 2%
        staleDataToleranceInSeconds: 2 days,
        maxAllowedDiscount: 0.05e18,
        lstPriceGapTolerance: 10 // 10 bps
     });

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, config);
        ILMPVaultFactory lmpFactory = systemRegistry.getLMPVaultFactoryByType(lmpVaultType);

        if (address(lmpFactory) == address(0)) {
            revert("LMP Vault Factory not set for weth-vault type");
        }

        lmpFactory.addStrategyTemplate(address(stratTemplate));
        console.log("LMP Strategy address: %s", address(stratTemplate));

        vm.stopBroadcast();
    }
}
