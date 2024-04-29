// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import {
    BAL_VAULT,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SFRXETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerLPComposableStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPComposableStableEthOracle private oracle;

    uint256 private mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_761_811);
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

    function testGetTotalSupply() public {
        uint256 totalSupply = oracle.getTotalSupply(WSETH_RETH_SFRXETH_BAL_POOL);

        assertEq(totalSupply, 1_256_611_294_351_516_040_784);
    }

    function testGetPoolTokens() public {
        (IERC20[] memory tokens, uint256[] memory balances) = oracle.getPoolTokens(WSETH_RETH_SFRXETH_BAL_POOL);

        assertEq(tokens.length, 3);
        assertEq(balances.length, 3);
        assertEq(address(tokens[0]), WSTETH_MAINNET);
        assertEq(address(tokens[1]), SFRXETH_MAINNET);
        assertEq(address(tokens[2]), RETH_MAINNET);

        assertEq(balances[0], 207_022_009_766_571_760_174);
        assertEq(balances[1], 785_068_062_152_840_745_060);
        assertEq(balances[2], 200_964_039_516_048_982_554);
    }
}
