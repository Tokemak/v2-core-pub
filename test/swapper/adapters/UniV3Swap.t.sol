// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { UniV3Swap } from "src/swapper/adapters/UniV3Swap.sol";

import { USDC_MAINNET, RANDOM, DAI_MAINNET, WETH9_ADDRESS, UNIV3_SWAP_ROUTER_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract UniV3SwapTest is Test {
    using Address for address;

    UniV3Swap private adapter;

    ISwapRouter.SwapData private route;

    uint24 private poolFee = 3000;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 16_728_070);
        vm.selectFork(forkId);

        adapter = new UniV3Swap(address(this));

        // route DAI_MAINNET -> WETH_MAINNET
        route = ISwapRouter.SwapData({
            token: WETH9_ADDRESS,
            pool: UNIV3_SWAP_ROUTER_MAINNET, // router
            swapper: adapter,
            data: abi.encodePacked(DAI_MAINNET, poolFee, USDC_MAINNET, poolFee, WETH9_ADDRESS)
        });
    }

    function test_validate_Revert_IfFromAddressMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "fromAddress"));
        adapter.validate(RANDOM, route);
    }

    function test_validate_Revert_IfToAddressMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "toAddress"));
        route.token = RANDOM;
        adapter.validate(DAI_MAINNET, route);
    }

    function test_validate_Works() public view {
        adapter.validate(DAI_MAINNET, route);
    }

    function test_swap_Works() public {
        uint256 sellAmount = 1e18;

        deal(DAI_MAINNET, address(this), 10 * sellAmount);
        IERC20(DAI_MAINNET).approve(address(adapter), 4 * sellAmount);

        // get balance of WETH_MAINNET before swap
        uint256 wethBalanceBefore = IERC20(WETH9_ADDRESS).balanceOf(address(this));

        bytes memory data = address(adapter).functionDelegateCall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, route.pool, DAI_MAINNET, sellAmount, WETH9_ADDRESS, 1, route.data
            )
        );

        // get balance of WETH_MAINNET after swap
        uint256 wethBalanceAfter = IERC20(WETH9_ADDRESS).balanceOf(address(this));
        uint256 val = abi.decode(data, (uint256));

        assertGt(wethBalanceAfter, wethBalanceBefore);

        // check that the amount of WETH received is equal to the amount returned by the swap function
        assertEq(val, wethBalanceAfter - wethBalanceBefore);
    }

    function test_swap_SingleWorks() public {
        ISwapRouter.SwapData memory singleroute = ISwapRouter.SwapData({
            token: WETH9_ADDRESS,
            pool: UNIV3_SWAP_ROUTER_MAINNET, // router
            swapper: adapter,
            data: abi.encodePacked(DAI_MAINNET, poolFee, WETH9_ADDRESS)
        });

        uint256 sellAmount = 1e18;

        deal(DAI_MAINNET, address(this), 10 * sellAmount);
        IERC20(DAI_MAINNET).approve(address(adapter), 4 * sellAmount);

        // get balance of WETH_MAINNET before swap
        uint256 wethBalanceBefore = IERC20(WETH9_ADDRESS).balanceOf(address(this));

        bytes memory data = address(adapter).functionDelegateCall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector,
                singleroute.pool,
                DAI_MAINNET,
                sellAmount,
                WETH9_ADDRESS,
                1,
                singleroute.data
            )
        );

        // get balance of WETH_MAINNET after swap
        uint256 wethBalanceAfter = IERC20(WETH9_ADDRESS).balanceOf(address(this));
        uint256 val = abi.decode(data, (uint256));

        assertGt(wethBalanceAfter, wethBalanceBefore);

        // check that the amount of WETH received is equal to the amount returned by the swap function
        assertEq(val, wethBalanceAfter - wethBalanceBefore);
    }
}
