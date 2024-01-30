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
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";
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
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

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
    uint256 public defaultRewardRatioLmp = 800;
    uint256 public defaultRewardBlockDurationLmp = 100;
    uint256 public defaultRewardRatioDest = 1;
    uint256 public defaultRewardBlockDurationDest = 1000;
    bytes32 public lmpVaultType = keccak256("lst-weth-v1");
    uint256 public startEpoch = block.timestamp;
    uint256 public minStakeDuration = 30 days;
    uint256 public lmp1SupplyLimit = type(uint112).max;
    uint256 public lmp1WalletLimit = type(uint112).max;
    string public lmp1SymbolSuffix = "EST";
    string public lmp1DescPrefix = "Established";
    bytes32 public lmp1Salt = keccak256("established");
    uint256 public lmp2SupplyLimit = type(uint112).max;
    uint256 public lmp2WalletLimit = type(uint112).max;
    string public lmp2SymbolSuffix = "EMRG";
    string public lmp2DescPrefix = "Emerging";
    bytes32 public lmp2Salt = keccak256("emerging");

    AccessController public accessController;
    SystemSecurity public systemSecurity;
    LMPVaultRegistry public lmpRegistry;
    LMPVault public lmpVaultTemplate;
    LMPVaultFactory public lmpFactory;
    LMPVaultRouter public lmpRouter;
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

        // LMP Registry setup.
        lmpRegistry = new LMPVaultRegistry(systemRegistry);
        systemRegistry.setLMPVaultRegistry(address(lmpRegistry));
        console.log("LMP Vault Registry address: ", address(lmpRegistry));

        // Deploy LMP Template.
        lmpVaultTemplate = new LMPVault(systemRegistry, wethAddress);
        console.log("LMP Template address: ", address(lmpVaultTemplate));

        // LMP Factory setup.
        lmpFactory = new LMPVaultFactory(
            systemRegistry, address(lmpVaultTemplate), defaultRewardRatioLmp, defaultRewardBlockDurationLmp
        );
        systemRegistry.setLMPVaultFactory(lmpVaultType, address(lmpFactory));
        accessController.setupRole(Roles.REGISTRY_UPDATER, address(lmpFactory));
        console.log("LMP Factory address: ", address(lmpFactory));

        // Initial LMP Vault creation.
        address establishedLmp =
            lmpFactory.createVault(lmp1SupplyLimit, lmp1WalletLimit, lmp1SymbolSuffix, lmp1DescPrefix, lmp1Salt, "");
        address emergingLmp =
            lmpFactory.createVault(lmp2SupplyLimit, lmp2WalletLimit, lmp2SymbolSuffix, lmp2DescPrefix, lmp2Salt, "");
        console.log("Established LMP Vault address: ", establishedLmp);
        console.log("Emerging LMP Vault address: ", emergingLmp);

        // LMP router setup.
        lmpRouter = new LMPVaultRouter(systemRegistry, wethAddress);
        systemRegistry.setLMPVaultRouter(address(lmpRouter));
        console.log("LMP Router address: ", address(lmpRouter));

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
        accessController.grantRole(Roles.REGISTRY_UPDATER, owner);
        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(constants.ext.zeroExProxy);
        asyncSwapperRegistry.register(address(zeroExSwapper));
        console.log("Base Async Swapper: ", address(zeroExSwapper));
        accessController.revokeRole(Roles.REGISTRY_UPDATER, owner);

        // Lens
        Lens lens = new Lens(systemRegistry);
        console.log("Lens: ", address(lens));

        // Setup our core reward tokens
        systemRegistry.addRewardToken(constants.tokens.weth);
        systemRegistry.addRewardToken(constants.tokens.toke);

        vm.stopBroadcast();
    }
}
