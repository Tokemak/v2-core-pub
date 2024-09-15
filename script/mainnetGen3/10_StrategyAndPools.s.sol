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
import { PointsHook } from "src/strategy/hooks/PointsHook.sol";
import { ERC4626RateProvider } from "src/external/balancer/ERC4626RateProvider.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";

contract StrategyAndPoolDeploy is Script {
    bytes32 public autopoolType = keccak256("lst-lrt-weth-v1");

    // 12.05 sec per block
    // 86400 seconds in a day
    // 100382 block reward duration === (86400 * 14) / 12.05
    uint256 public rewardDurationInBlock = 100_382;
    uint256 public newRewardRatio = 830;

    string public symbol = "autoETH";
    string public name = "Tokemak autoETH";

    string public balEthSymbol = "balETH";
    string public balEthName = "Balancer/Tokemak balETH";

    string public lrtSymbol = "autoLRT";
    string public lrtName = "Tokemak autoLRT";

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        // Deploy Autopool template
        AutopoolETH autoPoolTemplate =
            new AutopoolETH(constants.sys.systemRegistry, address(constants.sys.systemRegistry.weth()));
        console.log("Autopool Template: ", address(autoPoolTemplate));

        // Deploy and register factory for Autopool template
        AutopoolFactory autoPoolFactory = new AutopoolFactory(
            constants.sys.systemRegistry, address(autoPoolTemplate), newRewardRatio, rewardDurationInBlock
        );
        constants.sys.systemRegistry.setAutopoolFactory(autopoolType, address(autoPoolFactory));
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        console.log("AutopoolETH Factory: ", address(autoPoolFactory));

        // Deploy non-hook strategy template
        AutopoolETHStrategy strategyTemplate =
            new AutopoolETHStrategy(constants.sys.systemRegistry, getStrategyConfig());
        console.log("Autopool Strategy Template (No Hook): ", address(strategyTemplate));

        // Deploy hook strategy template
        PointsHook pointsHook = new PointsHook(constants.sys.systemRegistry, 0.1e18);
        console.log("Points Hook: ", address(pointsHook));
        AutopoolETHStrategyConfig.StrategyConfig memory strategyHookConfig = getStrategyConfig();
        strategyHookConfig.hooks[0] = address(pointsHook);
        AutopoolETHStrategy hookStrategyTemplate =
            new AutopoolETHStrategy(constants.sys.systemRegistry, strategyHookConfig);
        console.log("Autopool Strategy Template (Points Hook): ", address(hookStrategyTemplate));

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FACTORY_MANAGER, owner);
        autoPoolFactory.addStrategyTemplate(address(strategyTemplate));
        autoPoolFactory.addStrategyTemplate(address(hookStrategyTemplate));
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FACTORY_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        uint256 initialDeposit = autoPoolTemplate.WETH_INIT_DEPOSIT();
        uint256 saltStart = block.number;

        address autoEthPool = autoPoolFactory.createVault{ value: initialDeposit }(
            address(strategyTemplate), symbol, name, keccak256(abi.encodePacked(saltStart)), ""
        );
        console.log("autoETH address: ", autoEthPool);

        address balEthPool = autoPoolFactory.createVault{ value: initialDeposit }(
            address(strategyTemplate), balEthSymbol, balEthName, keccak256(abi.encodePacked(saltStart + 1)), ""
        );
        console.log("balETH address: ", balEthPool);

        address lrtPool = autoPoolFactory.createVault{ value: initialDeposit }(
            address(hookStrategyTemplate), lrtSymbol, lrtName, keccak256(abi.encodePacked(saltStart + 2)), ""
        );
        console.log("autoLRT address: ", lrtPool);

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        ERC4626RateProvider balEthRateProvider = new ERC4626RateProvider(IERC4626(balEthPool));
        console.log("balETH Rate Provider: ", address(balEthRateProvider));

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
                initInDays: 50,
                tightenThresholdInViolations: 5,
                tightenStepInDays: 2,
                relaxThresholdInDays: 30,
                relaxStepInDays: 1,
                maxInDays: 60,
                minInDays: 14
            }),
            navLookback: AutopoolETHStrategyConfig.NavLookbackConfig({
                lookback1InDays: 30,
                lookback2InDays: 60,
                lookback3InDays: 90
            }),
            slippage: AutopoolETHStrategyConfig.SlippageConfig({
                maxNormalOperationSlippage: 1e16, // 1.0%
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
            pauseRebalancePeriodInDays: 30,
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
