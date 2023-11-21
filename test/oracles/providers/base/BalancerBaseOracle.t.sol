// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerBaseOracle } from "src/oracles/providers/base/BalancerBaseOracle.sol";

import {
    BAL_VAULT,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SFRXETH_MAINNET,
    WETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerBaseOracleWrapper is BalancerBaseOracle {
    constructor(
        ISystemRegistry _systemRegistry,
        IVault _balancerVault
    ) BalancerBaseOracle(_systemRegistry, _balancerVault) { }
}

contract BalancerBaseOracleWrapperTests is Test {
    IVault internal constant VAULT = IVault(BAL_VAULT);
    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerBaseOracleWrapper internal oracle;

    uint256 private mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_951);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerBaseOracleWrapper(systemRegistry, VAULT);
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}

contract GetSpotPrice is BalancerBaseOracleWrapperTests {
    /// @dev rEth -> sfrxETH at block 17_378_951 is 1.029499830936747431.
    /// Pool has no WETH so it returns sfrxETH
    function test_getSpotPrice_withWETHQuote() public {
        (uint256 price, address quoteToken) =
            oracle.getSpotPrice(RETH_MAINNET, WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET);

        assertEq(quoteToken, SFRXETH_MAINNET);
        assertEq(price, 1_029_499_830_936_747_431);
    }

    /// @dev rEth -> wstETH at block 17_378_951 is 0.952518727388269243.
    function test_getSpotPrice_withoutWETHQuote() public {
        (uint256 price, address quoteToken) = oracle.getSpotPrice(
            RETH_MAINNET, // rEth
            WSETH_RETH_SFRXETH_BAL_POOL,
            WSTETH_MAINNET // wstETH
        );

        assertEq(quoteToken, WSTETH_MAINNET);
        assertEq(price, 952_518_727_388_269_243);
    }
}
