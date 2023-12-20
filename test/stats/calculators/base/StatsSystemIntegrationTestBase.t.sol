// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";

import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import {
    WSTETH_MAINNET,
    TOKE_MAINNET,
    WETH_MAINNET,
    CURVE_ETH,
    CURVE_META_REGISTRY_MAINNET,
    BAL_VAULT
} from "test/utils/Addresses.sol";

contract StatsSystemIntegrationTestBase is Test {
    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    RootPriceOracle internal _rootPriceOracle;
    SystemSecurity internal _systemSecurity;
    StatsCalculatorFactory internal _statsFactory;
    StatsCalculatorRegistry internal _statsRegistry;
    CurveResolverMainnet internal _curveResolver;
    IncentivePricingStats internal _incentivePricing;

    ChainlinkOracle internal _chainlinkOracle;
    EthPeggedOracle internal _ethPeggedOracle;
    CurveV1StableEthOracle internal _curveV1Oracle;
    BalancerLPMetaStableEthOracle internal _balancerMetaOracle;
    WstETHEthOracle internal _wstEthOracle;

    function setUp(uint256 forkBlockNumber) internal virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), forkBlockNumber);

        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        vm.makePersistent(address(_systemRegistry));

        _accessController = new AccessController(address(_systemRegistry));
        vm.makePersistent(address(_accessController));
        _systemRegistry.setAccessController(address(_accessController));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        vm.makePersistent(address(_systemSecurity));
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        _statsRegistry = new StatsCalculatorRegistry(_systemRegistry);
        vm.makePersistent(address(_statsRegistry));
        _systemRegistry.setStatsCalculatorRegistry(address(_statsRegistry));

        _statsFactory = new StatsCalculatorFactory(_systemRegistry);
        vm.makePersistent(address(_statsFactory));
        _statsRegistry.setCalculatorFactory(address(_statsFactory));

        _rootPriceOracle = new RootPriceOracle(_systemRegistry);
        vm.makePersistent(address(_rootPriceOracle));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        _curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        vm.makePersistent(address(_curveResolver));
        _systemRegistry.setCurveResolver(address(_curveResolver));

        _chainlinkOracle = new ChainlinkOracle(_systemRegistry);
        _ethPeggedOracle = new EthPeggedOracle(_systemRegistry);
        _curveV1Oracle = new CurveV1StableEthOracle(_systemRegistry, _curveResolver);
        _balancerMetaOracle = new BalancerLPMetaStableEthOracle(_systemRegistry, IBalancerVault(BAL_VAULT));
        _wstEthOracle = new WstETHEthOracle(_systemRegistry, WSTETH_MAINNET);

        vm.makePersistent(address(_chainlinkOracle));
        vm.makePersistent(address(_ethPeggedOracle));
        vm.makePersistent(address(_curveV1Oracle));
        vm.makePersistent(address(_balancerMetaOracle));
        vm.makePersistent(address(_wstEthOracle));

        _rootPriceOracle.registerMapping(WETH_MAINNET, _ethPeggedOracle);
        _rootPriceOracle.registerMapping(CURVE_ETH, _ethPeggedOracle);
        _rootPriceOracle.registerMapping(WSTETH_MAINNET, _wstEthOracle);

        _accessController.grantRole(Roles.STATS_CALC_TEMPLATE_MGMT_ROLE, address(this));
        _accessController.grantRole(Roles.CREATE_STATS_CALC_ROLE, address(this));
        _accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));
        _accessController.grantRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, address(this));

        _incentivePricing = new IncentivePricingStats(_systemRegistry);
        _systemRegistry.setIncentivePricingStats(address(_incentivePricing));
        vm.makePersistent(address(_incentivePricing));
    }
}
