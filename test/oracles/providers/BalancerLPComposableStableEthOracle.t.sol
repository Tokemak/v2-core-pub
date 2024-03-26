// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import {
    BAL_VAULT,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SFRXETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL,
    CBETH_MAINNET,
    UNI_ETH_MAINNET,
    WETH_MAINNET,
    DAI_MAINNET,
    USDC_MAINNET,
    UNI_WETH_POOL,
    USDT_MAINNET,
    CBETH_WSTETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerLPComposableStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);
    address private constant WSTETH = address(WSTETH_MAINNET);
    address private constant RETH = address(RETH_MAINNET);
    address private constant SFRXETH = address(SFRXETH_MAINNET);
    address private constant WSTETH_RETH_SFRXETH_POOL = address(WSETH_RETH_SFRXETH_BAL_POOL);
    address private constant UNIETH = address(UNI_ETH_MAINNET);
    address private constant WETH = address(WETH_MAINNET);
    address private constant UNIETH_WETH_POOL = address(UNI_WETH_POOL);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPComposableStableEthOracle private oracle;

    uint256 private mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_951);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPComposableStableEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}
