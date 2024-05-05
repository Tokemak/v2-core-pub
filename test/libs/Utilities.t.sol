// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { Utilities } from "src/libs/Utilities.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";

contract UtilitiesTest is Test {
    IERC20Metadata internal testTokenMetadata = IERC20Metadata(WETH_MAINNET);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function test_getScaleDownFactor() public {
        // >18 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(24));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 4);

        // 18 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 4);

        // >6 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(7));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 3);

        // 6 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 2);

        // >2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(3));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 1);

        // 2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(2));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 0);

        // <2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(1));
        assertEq(Utilities.getScaleDownFactor(testTokenMetadata), 0);
    }

    function test_getScaledDownDecimals() public {
        // >18 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(24));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 20);

        // 18 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 14);

        // >6 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(7));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 4);

        // 6 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 4);

        // >2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(3));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 2);

        // 2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(2));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 2);

        // <2 decimals
        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(1));
        assertEq(Utilities.getScaledDownDecimals(testTokenMetadata), 1);
    }
}
