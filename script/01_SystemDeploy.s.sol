// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { BaseScript, console } from "./BaseScript.sol";

// Contracts
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { AutoPoolRegistry } from "src/vault/AutoPoolRegistry.sol";
import { AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { AutoPoolFactory } from "src/vault/AutoPoolFactory.sol";
import { AutoPilotRouter } from "src/vault/AutoPilotRouter.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { Lens } from "src/lens/Lens.sol";

// Libraries
import { Roles } from "src/libs/Roles.sol";
import { Systems } from "./utils/Constants.sol";

// Interfaces
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

/**
 * @dev FIRST GROUP OF STATE VARIABLES MUST BE MANUALLY SET!  DO NOT BROADCAST THIS SCRIPT TO MAINNET WITHOUT
 *      FIRST CHECKING THAT THESE VARIABLES WORK!
 *
 * @dev Check `.env.example` for environment variables that need are needed for this script to run.
 *
 * @dev This script sets up base functionality for TokemakV2.  This includes setting up the system registry, all
 *      contracts that are set on the system registry, and their dependencies.  All other actions within the system
 *      will be handled via other scripts.
 *
 * @dev To deploy test this script locally against a fork, run the following:
 *      `forge script script/01_SystemDeploy.s.sol --rpc-url<YOUR_URL_HERE>`.
 *
 *      To broadcast these transactions to the chain your rpc url points to, add the `--broadcast` flag.
 *
 *      To verify these contracts on Etherscan, add the `--verify` flag.
 */
contract DeploySystem is BaseScript {
    /// @dev Manually set variables below.
    uint256 public defaultRewardRatioAutoPool = 800;
    uint256 public defaultRewardBlockDurationAutoPool = 100;
    uint256 public defaultRewardRatioDest = 1;
    uint256 public defaultRewardBlockDurationDest = 1000;
    bytes32 public autoPoolType = keccak256("lst-weth-v1");
    uint256 public startEpoch = block.timestamp;
    uint256 public minStakeDuration = 30 days;
    uint256 public autoPool1SupplyLimit = type(uint112).max;
    uint256 public autoPool1WalletLimit = type(uint112).max;
    string public autoPool1SymbolSuffix = "EST";
    string public autoPool1DescPrefix = "Established";
    bytes32 public autoPool1Salt = keccak256("established");
    uint256 public autoPool2SupplyLimit = type(uint112).max;
    uint256 public autoPool2WalletLimit = type(uint112).max;
    string public autoPool2SymbolSuffix = "EMRG";
    string public autoPool2DescPrefix = "Emerging";
    bytes32 public autoPool2Salt = keccak256("emerging");

    SystemSecurity public systemSecurity;
    AutoPoolRegistry public autoPoolRegistry;
    AutoPoolETH public autoPoolTemplate;
    AutoPoolFactory public autoPoolFactory;
    AutoPilotRouter public autoPoolRouter;
    DestinationRegistry public destRegistry;
    DestinationVaultRegistry public destVaultRegistry;
    DestinationVaultFactory public destVaultFactory;
    SwapRouter public swapRouter;
    AsyncSwapperRegistry public asyncSwapperRegistry;
    RootPriceOracle public priceOracle;
    StatsCalculatorRegistry public statsRegistry;
    AccToke public accToke;

    CurveResolverMainnet public curveResolver;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        address owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        vm.startBroadcast(privateKey);

        // System registry setup
        systemRegistry = new SystemRegistry(tokeAddress, wethAddress);
        systemRegistry.addRewardToken(tokeAddress);
        console.log("System Registry address: ", address(systemRegistry));

        // Access controller setup.
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        console.log("Access Controller address: ", address(accessController));

        // System security setup
        systemSecurity = new SystemSecurity(systemRegistry);
        systemRegistry.setSystemSecurity(address(systemSecurity));
        console.log("System Security address: ", address(systemSecurity));

        // AutoPool Registry setup.
        autoPoolRegistry = new AutoPoolRegistry(systemRegistry);
        systemRegistry.setAutoPoolRegistry(address(autoPoolRegistry));
        console.log("AutoPool Vault Registry address: ", address(autoPoolRegistry));

        // Deploy AutoPool Template.
        autoPoolTemplate = new AutoPoolETH(systemRegistry, wethAddress);
        console.log("AutoPool Template address: ", address(autoPoolTemplate));

        // AutoPool Factory setup.
        autoPoolFactory = new AutoPoolFactory(
            systemRegistry, address(autoPoolTemplate), defaultRewardRatioAutoPool, defaultRewardBlockDurationAutoPool
        );
        systemRegistry.setAutoPoolFactory(autoPoolType, address(autoPoolFactory));
        accessController.setupRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        console.log("AutoPool Factory address: ", address(autoPoolFactory));

        // Initial AutoPool Vault creation.
        // address establishedAutoPool =
        //     autoPoolFactory.createVault(autoPool1SupplyLimit, autoPool1WalletLimit, autoPool1SymbolSuffix,
        // autoPool1DescPrefix, autoPool1Salt, "");
        // address emergingAutoPool =
        //     autoPoolFactory.createVault(autoPool2SupplyLimit, autoPool2WalletLimit, autoPool2SymbolSuffix,
        // autoPool2DescPrefix, autoPool2Salt, "");
        // console.log("Established AutoPool Vault address: ", establishedAutoPool);
        // console.log("Emerging AutoPool Vault address: ", emergingAutoPool);

        // AutoPool router setup.
        autoPoolRouter = new AutoPilotRouter(systemRegistry);
        systemRegistry.setAutoPilotRouter(address(autoPoolRouter));
        console.log("AutoPool Router address: ", address(autoPoolRouter));

        // Destination registry setup.
        destRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destRegistry));
        console.log("Destination Registry address: ", address(destRegistry));

        // Destination vault registry setup.
        destVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destVaultRegistry));
        console.log("Destination Vault Registry address: ", address(destVaultRegistry));

        // Destination vault factory setup.
        destVaultFactory =
            new DestinationVaultFactory(systemRegistry, defaultRewardRatioDest, defaultRewardBlockDurationDest);
        destVaultRegistry.setVaultFactory(address(destVaultFactory));
        console.log("Destination Vault Factory address: ", address(destVaultFactory));

        // Swap router setup.
        swapRouter = new SwapRouter(systemRegistry);
        systemRegistry.setSwapRouter(address(swapRouter));
        console.log("Swap Router address: ", address(swapRouter));

        // Async swapper setup.
        asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));
        console.log("Async Swapper Registry address: ", address(asyncSwapperRegistry));

        // Price oracle setup.
        priceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(priceOracle));
        console.log("Price Oracle address: ", address(priceOracle));

        // Stats registry setup.
        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));
        console.log("Stats Calculator Registry address: ", address(statsRegistry));

        // accToke setup.
        accToke = new AccToke(systemRegistry, startEpoch, minStakeDuration);
        systemRegistry.setAccToke(address(accToke));
        console.log("AccToke address: ", address(accToke));

        // Curve resolver setup.
        if (curveMetaRegistryAddress != address(0)) {
            curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(curveMetaRegistryAddress));
            systemRegistry.setCurveResolver(address(curveResolver));
            console.log("Curve Resolver Address: ", address(curveResolver));
        }

        // Setup the 0x swapper
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, owner);
        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(constants.ext.zeroExProxy);
        asyncSwapperRegistry.register(address(zeroExSwapper));
        console.log("Base Async Swapper: ", address(zeroExSwapper));
        accessController.revokeRole(Roles.AUTO_POOL_REGISTRY_UPDATER, owner);

        // Lens
        Lens lens = new Lens(systemRegistry);
        console.log("Lens: ", address(lens));

        // Setup our core reward tokens
        systemRegistry.addRewardToken(constants.tokens.weth);
        systemRegistry.addRewardToken(constants.tokens.toke);

        vm.stopBroadcast();
    }
}
