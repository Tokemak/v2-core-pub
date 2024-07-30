// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { AutopoolETHStrategyConfig } from "src/strategy/AutopoolETHStrategyConfig.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";

contract NewPoolAndStrategy is Script {
    bytes32 public autopoolType = keccak256("lst-guarded-weth-v1");

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        AutopoolETH autoPoolTemplate =
            new AutopoolETH(constants.sys.systemRegistry, address(constants.sys.systemRegistry.weth()));
        console.log("Autopool Template: ", address(autoPoolTemplate));

        AutopoolFactory autoPoolFactory =
            new AutopoolFactory(constants.sys.systemRegistry, address(autoPoolTemplate), 800, 100);
        constants.sys.systemRegistry.setAutopoolFactory(autopoolType, address(autoPoolFactory));
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        console.log("AutopoolETH Factory: ", address(autoPoolFactory));

        AutopoolETHStrategy strategyTemplate =
            new AutopoolETHStrategy(constants.sys.systemRegistry, getStrategyConfig());
        console.log("Autopool Strategy Template: ", address(strategyTemplate));

        autoPoolFactory.addStrategyTemplate(address(strategyTemplate));

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        uint256 initialDeposit = autoPoolTemplate.WETH_INIT_DEPOSIT();
        constants.sys.systemRegistry.weth().deposit{ value: initialDeposit }();
        constants.sys.systemRegistry.weth().approve(address(autoPoolFactory), initialDeposit);
        address autoPool = autoPoolFactory.createVault{ value: initialDeposit }(
            address(strategyTemplate),
            "baseETH_guarded",
            "Tokemak Guarded baseETH",
            keccak256(abi.encodePacked(block.number)),
            ""
        );

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        console.log("Autopool address: ", autoPool);

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);
        address[] memory destinationsToAdd = new address[](2);
        destinationsToAdd[0] = 0xbE236370c77484686E1E542A85466778c3745203;
        destinationsToAdd[1] = 0xd68096B2810D56b94e837c3CA9613276bc467675;
        AutopoolETH(autoPool).addDestinations(destinationsToAdd);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        vm.stopBroadcast();

        console.log("\n\n  **************************************");
        console.log("======================================");
        console.log("Remember to put any libraries that were deployed into the foundry.toml");
        console.log("======================================");
        console.log("**************************************\n\n");
    }

    function getStrategyConfig() internal pure returns (AutopoolETHStrategyConfig.StrategyConfig memory) {
        return AutopoolETHStrategyConfig.StrategyConfig({
            swapCostOffset: AutopoolETHStrategyConfig.SwapCostOffsetConfig({
                initInDays: 60,
                tightenThresholdInViolations: 5,
                tightenStepInDays: 2,
                relaxThresholdInDays: 30,
                relaxStepInDays: 1,
                maxInDays: 60,
                minInDays: 7
            }),
            navLookback: AutopoolETHStrategyConfig.NavLookbackConfig({
                lookback1InDays: 30,
                lookback2InDays: 60,
                lookback3InDays: 90
            }),
            slippage: AutopoolETHStrategyConfig.SlippageConfig({
                maxNormalOperationSlippage: 5e15, // 0.5%
                maxTrimOperationSlippage: 2e16, // 2%
                maxEmergencyOperationSlippage: 0.1e18, // 10%
                maxShutdownOperationSlippage: 0.015e18 // 1.5%
             }),
            modelWeights: AutopoolETHStrategyConfig.ModelWeights({
                baseYield: 1e6,
                feeYield: 1e6,
                incentiveYield: 0.9e6,
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
            lstPriceGapTolerance: 10, // 10 bps
            hooks: [address(0), address(0), address(0), address(0), address(0)]
        });
    }
}
