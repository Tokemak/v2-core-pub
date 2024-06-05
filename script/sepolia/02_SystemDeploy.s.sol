// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

// Contracts
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurityL1 } from "src/security/SystemSecurityL1.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { Lens } from "src/lens/Lens.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";

// Libraries
import { Roles } from "src/libs/Roles.sol";
import { Systems, Constants } from "../utils/Constants.sol";

// Interfaces
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

contract DeploySystem is Script {
    /// @dev Manually set variables below.

    // Rewarders
    uint256 public defaultRewardRatioAutopool = 800;
    uint256 public defaultRewardBlockDurationAutopool = 100;
    uint256 public defaultRewardRatioDest = 1;
    uint256 public defaultRewardBlockDurationDest = 1000;

    // Acc
    uint256 public startEpoch = block.timestamp;
    uint256 public minStakeDuration = 30 days;

    SystemRegistry public systemRegistry;
    AccessController public accessController;
    SystemSecurityL1 public systemSecurity;
    AutopoolRegistry public autoPoolRegistry;
    AutopilotRouter public autoPoolRouter;
    DestinationRegistry public destRegistry;
    DestinationVaultRegistry public destVaultRegistry;
    DestinationVaultFactory public destVaultFactory;
    SwapRouter public swapRouter;
    AsyncSwapperRegistry public asyncSwapperRegistry;
    RootPriceOracle public priceOracle;
    StatsCalculatorRegistry public statsRegistry;
    AccToke public accToke;
    CurveResolverMainnet public curveResolver;
    IncentivePricingStats public incentivePricingStats;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        Constants.Values memory values = Constants.get(Systems.NEW_SEPOLIA);

        deployCore(values, owner);

        vm.stopBroadcast();
    }

    function deployCore(Constants.Values memory values, address owner) internal {
        // System registry setup
        systemRegistry = new SystemRegistry(values.tokens.toke, values.tokens.weth);
        systemRegistry.addRewardToken(values.tokens.toke);
        systemRegistry.addRewardToken(values.tokens.weth);
        console.log("System Registry: ", address(systemRegistry));

        // Access controller setup.
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        console.log("Access Controller: ", address(accessController));

        // System security setup
        systemSecurity = new SystemSecurityL1(systemRegistry);
        systemRegistry.setSystemSecurity(address(systemSecurity));
        console.log("System Security: ", address(systemSecurity));

        // Autopool Registry setup.
        autoPoolRegistry = new AutopoolRegistry(systemRegistry);
        systemRegistry.setAutopoolRegistry(address(autoPoolRegistry));
        console.log("Autopool Registry: ", address(autoPoolRegistry));

        // Destination registry setup.
        destRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destRegistry));
        console.log("Destination Template Registry: ", address(destRegistry));

        // Destination vault registry setup.
        destVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destVaultRegistry));
        console.log("Destination Vault Registry: ", address(destVaultRegistry));

        // Destination vault factory setup.
        accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);
        destVaultFactory =
            new DestinationVaultFactory(systemRegistry, defaultRewardRatioDest, defaultRewardBlockDurationDest);
        destVaultRegistry.setVaultFactory(address(destVaultFactory));
        console.log("Destination Vault Factory: ", address(destVaultFactory));
        accessController.revokeRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        // Swap router setup.
        swapRouter = new SwapRouter(systemRegistry);
        systemRegistry.setSwapRouter(address(swapRouter));
        console.log("Swap Router: ", address(swapRouter));

        // Async swapper setup.
        asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));
        console.log("Async Swapper Registry: ", address(asyncSwapperRegistry));

        // Price oracle setup.
        priceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(priceOracle));
        console.log("Root Price Oracle: ", address(priceOracle));

        // Stats registry setup.
        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));
        console.log("Stats Calculator Registry: ", address(statsRegistry));

        StatsCalculatorFactory statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));
        console.log("Stats Calculator Factory: ", address(statsFactory));

        // accToke setup.
        accToke = new AccToke(systemRegistry, startEpoch, minStakeDuration);
        systemRegistry.setAccToke(address(accToke));
        console.log("AccToke: ", address(accToke));

        // Curve resolver setup.
        if (values.ext.curveMetaRegistry != address(0)) {
            curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(values.ext.curveMetaRegistry));
            systemRegistry.setCurveResolver(address(curveResolver));
            console.log("Curve Resolver: ", address(curveResolver));
        }

        // Setup the 0x swapper
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, owner);
        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(values.ext.zeroExProxy);
        asyncSwapperRegistry.register(address(zeroExSwapper));
        console.log("Base Async Swapper: ", address(zeroExSwapper));
        accessController.revokeRole(Roles.AUTO_POOL_REGISTRY_UPDATER, owner);

        // Lens
        Lens lens = new Lens(systemRegistry);
        console.log("Lens: ", address(lens));

        // Incentive Pricing
        incentivePricingStats = new IncentivePricingStats(systemRegistry);
        systemRegistry.setIncentivePricingStats(address(incentivePricingStats));
        console.log("Incentive Pricing Stats: ", address(incentivePricingStats));
    }
}
