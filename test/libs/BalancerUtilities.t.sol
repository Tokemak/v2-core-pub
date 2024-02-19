// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase

import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import {
    WSETH_RETH_SFRXETH_BAL_POOL,
    WSETH_WETH_BAL_POOL,
    RETH_WETH_BAL_POOL,
    BAL_VAULT,
    WSTETH_MAINNET,
    SFRXETH_MAINNET,
    RETH_MAINNET
} from "test/utils/Addresses.sol";

contract BalancerUtilitiesTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_735_327);
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

    function test_getPoolTokens_ReturnsProperValues() public {
        (IERC20[] memory assets, uint256[] memory balances) =
            BalancerUtilities._getPoolTokens(IVault(BAL_VAULT), WSETH_RETH_SFRXETH_BAL_POOL);

        // Verify assets
        assertEq(assets.length, 4);
        assertEq(address(assets[0]), WSETH_RETH_SFRXETH_BAL_POOL); // pool token
        assertEq(address(assets[1]), WSTETH_MAINNET);
        assertEq(address(assets[2]), SFRXETH_MAINNET);
        assertEq(address(assets[3]), RETH_MAINNET);
        // Verify balances
        assertEq(balances.length, 4);
        assertEq(balances[0], 2_596_148_429_266_377_841_425_127_555_671_541);
        assertEq(balances[1], 380_949_500_227_632_620_189);
        assertEq(balances[2], 634_919_600_886_552_074_720);
        assertEq(balances[3], 166_972_211_148_502_452_054);
    }

    function test_getPoolTokensSkippingPoolToken_ReturnsProperValues() public {
        (IERC20[] memory assets, uint256[] memory balances) =
            BalancerUtilities._getPoolTokens(IVault(BAL_VAULT), WSETH_RETH_SFRXETH_BAL_POOL);

        // Verify assets
        assertEq(assets.length, 4);
        assertEq(address(assets[0]), WSETH_RETH_SFRXETH_BAL_POOL); // pool token
        assertEq(address(assets[1]), WSTETH_MAINNET);
        assertEq(address(assets[2]), SFRXETH_MAINNET);
        assertEq(address(assets[3]), RETH_MAINNET);
        // Verify balances
        assertEq(balances.length, 4);
        assertEq(balances[0], 2_596_148_429_266_377_841_425_127_555_671_541);
        assertEq(balances[1], 380_949_500_227_632_620_189);
        assertEq(balances[2], 634_919_600_886_552_074_720);
        assertEq(balances[3], 166_972_211_148_502_452_054);
    }

    function test_getComposablePoolTokensSkipBpt_ReturnsProperValues_AndFiltersPoolToken() public {
        (IERC20[] memory assets, uint256[] memory balances) =
            BalancerUtilities._getComposablePoolTokensSkipBpt(IVault(BAL_VAULT), WSETH_RETH_SFRXETH_BAL_POOL);

        // Verify assets
        assertEq(assets.length, 3);
        assertEq(address(assets[0]), WSTETH_MAINNET);
        assertEq(address(assets[1]), SFRXETH_MAINNET);
        assertEq(address(assets[2]), RETH_MAINNET);
        // Verify balances
        assertEq(balances.length, 3);
        assertEq(balances[0], 380_949_500_227_632_620_189);
        assertEq(balances[1], 634_919_600_886_552_074_720);
        assertEq(balances[2], 166_972_211_148_502_452_054);
    }

    function test_getMetaStableVirtualPrice_UnscaledInvariant() public {
        // lastInvariant: 35_243_135_001_415_568_139_348
        // unscaledInv = (virtualPrice * totalSupply) / 1e18:
        // (1_028_137_102_910_976_515 * 34_278_666_982_700_538_202_249) / 1e18 = 35_243_169_363_243_876_067_846

        uint256 virtualPrice = BalancerUtilities._getMetaStableVirtualPrice(IVault(BAL_VAULT), RETH_WETH_BAL_POOL);

        assertEq(virtualPrice, 1_028_136_601_697_957_857);
    }

    function test_getMetaStableVirtualPrice_LastInvariant() public {
        // unscaledInv = (virtualPrice * totalSupply) / 1e18:
        // (1_028_137_102_910_976_515 * 34_278_666_982_700_538_202_249) / 1e18 = 35_243_169_363_243_876_067_846

        // Mock lastInvariant to be > unscaledInv
        vm.mockCall(
            RETH_WETH_BAL_POOL,
            abi.encodeWithSelector(IBalancerMetaStablePool.getLastInvariant.selector),
            abi.encode(35_243_169_363_243_876_067_846 + 100)
        );

        uint256 virtualPrice = BalancerUtilities._getMetaStableVirtualPrice(IVault(BAL_VAULT), RETH_WETH_BAL_POOL);

        assertEq(virtualPrice, 1_028_137_102_910_976_515);
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
