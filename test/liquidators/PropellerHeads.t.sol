// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BaseAsyncSwapper } from "../../src/liquidation/BaseAsyncSwapper.sol";
import { IAsyncSwapper, SwapParams } from "../../src/interfaces/liquidation/IAsyncSwapper.sol";
import { PRANK_ADDRESS, CVX_MAINNET, WETH_MAINNET, PROPELLER_HEADS_MAINNET } from "../utils/Addresses.sol";
import { console } from "forge-std/console.sol";

// solhint-disable func-name-mixedcase
contract PropellerHeadsTest is Test {
    BaseAsyncSwapper private adapter;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 19_677_004);
        vm.selectFork(forkId);

        adapter = new BaseAsyncSwapper(PROPELLER_HEADS_MAINNET);
    }

    function test_Revert_IfBuyTokenAddressIsZeroAddress() public {
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 0, address(0), 0, new bytes(0), new bytes(0)));
    }

    function test_Revert_IfSellTokenAddressIsZeroAddress() public {
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        adapter.swap(SwapParams(address(0), 0, PRANK_ADDRESS, 0, new bytes(0), new bytes(0)));
    }

    function test_Revert_IfSellAmountIsZero() public {
        vm.expectRevert(IAsyncSwapper.InsufficientSellAmount.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 0, PRANK_ADDRESS, 1, new bytes(0), new bytes(0)));
    }

    function test_Revert_IfBuyAmountIsZero() public {
        vm.expectRevert(IAsyncSwapper.InsufficientBuyAmount.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 1, PRANK_ADDRESS, 0, new bytes(0), new bytes(0)));
    }

    function test_swap() public {
        // solhint-disable max-line-length
        bytes memory data =
            hex"6e5129d10000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000c20000000000000000000000000000000000000000000000056bc75e2d631000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000000000000000000000000000012d8dd54fcdf4a0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc25615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0005767d9ef41dc40689678ffca0608878fb3de9065615deb798bb3e4dfa0139dfa1b3d433cc23b72f0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004109500c1e85a40d36a4992a18d557a52ad25896a0aa3529dccf298be4a13650223d73db906a16153b6d91c0de107b88eabcc753012733b2c7e76edc778819aa4e1c00000000000000000000000000000000000000000000000000000000000000";

        deal(CVX_MAINNET, address(adapter), 100e18);

        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(adapter));

        console.log(address(adapter));
        adapter.swap(SwapParams(CVX_MAINNET, 100e18, WETH_MAINNET, 80_719_887_656_811_836, data, new bytes(0)));

        uint256 balanceAfter = IERC20(WETH_MAINNET).balanceOf(address(adapter));
        uint256 balanceDiff = balanceAfter - balanceBefore;

        assertTrue(balanceDiff >= 80_719_887_656_811_836);
    }
}
