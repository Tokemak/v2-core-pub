// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase

import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import {
    WSETH_RETH_SFRXETH_BAL_POOL,
    WSETH_WETH_BAL_POOL,
    BAL_VAULT,
    WSTETH_MAINNET,
    SFRXETH_MAINNET,
    RETH_MAINNET
} from "test/utils/Addresses.sol";

contract BalancerUtilitiesTest is Test {
    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
    }

    function test_isComposablePool_ReturnsTrueOnValidComposable() public {
        assertTrue(BalancerUtilities.isComposablePool(WSETH_RETH_SFRXETH_BAL_POOL));
    }

    function test_isComposablePool_ReturnsFalseOnMetastable() public {
        assertFalse(BalancerUtilities.isComposablePool(WSETH_WETH_BAL_POOL));
    }

    function test_isComposablePool_ReturnsFalseOnEOA() public {
        assertFalse(BalancerUtilities.isComposablePool(vm.addr(5)));
    }

    function test_isComposablePool_ReturnsFalseOnInvalidContract() public {
        assertFalse(BalancerUtilities.isComposablePool(address(new Noop())));
    }

    function test_getPoolTokens_ReturnsProperAddresses() public {
        IVault balancerVault = IVault(BAL_VAULT);
        address balancerPool = WSETH_RETH_SFRXETH_BAL_POOL;

        (IERC20[] memory assets,) = BalancerUtilities._getPoolTokens(balancerVault, balancerPool);

        assertEq(assets.length, 4);

        assertEq(address(assets[0]), WSETH_RETH_SFRXETH_BAL_POOL);
        assertEq(address(assets[1]), WSTETH_MAINNET);
        assertEq(address(assets[2]), SFRXETH_MAINNET);
        assertEq(address(assets[3]), RETH_MAINNET);
    }

    function test_ReentrancyGasUsage() external {
        uint256 gasLeftBeforeReentrancy = gasleft();
        BalancerUtilities.checkReentrancy(BAL_VAULT);
        uint256 gasleftAfterReentrancy = gasleft();

        /**
         *  20k gives ample buffer for other operations outside of staticcall to balancer vault, which
         *        is given 10k gas.  Operation above should take ~17k gas total.
         */
        assertLt(gasLeftBeforeReentrancy - gasleftAfterReentrancy, 20_000);
    }
}

contract Noop { }
