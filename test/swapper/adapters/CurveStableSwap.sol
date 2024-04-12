// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { CurveV2Swap } from "src/swapper/adapters/CurveV2Swap.sol";
import { ICurveV2Swap } from "src/interfaces/external/curve/ICurveV2Swap.sol";

import { LDO_MAINNET, WETH_MAINNET, RANDOM } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract CurveV2SwapTest is Test {
    CurveV2Swap private adapter;

    ISwapRouter.SwapData private route;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 16_728_070);
        vm.selectFork(forkId);

        adapter = new CurveV2Swap(address(this));

        // route WETH_MAINNET -> LDO_MAINNET
        route = ISwapRouter.SwapData({
            token: LDO_MAINNET,
            pool: 0x9409280DC1e6D33AB7A8C6EC03e5763FB61772B5,
            swapper: adapter,
            data: abi.encode(0, 1)
        });
    }

    function test_validate_Revert_IfFromAddressMismatch() public {
        // pretend that the pool doesn't have WETH_MAINNET
        vm.mockCall(route.pool, abi.encodeWithSelector(ICurveV2Swap.coins.selector, 0), abi.encode(RANDOM));
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "fromAddress"));
        adapter.validate(WETH_MAINNET, route);
    }

    function test_validate_Revert_IfToAddressMismatch() public {
        // pretend that the pool doesn't have LDO_MAINNET
        vm.mockCall(route.pool, abi.encodeWithSelector(ICurveV2Swap.coins.selector, 1), abi.encode(RANDOM));
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "toAddress"));
        adapter.validate(WETH_MAINNET, route);
    }

    function test_validate_Works() public view {
        adapter.validate(WETH_MAINNET, route);
    }

    function test_swap_Works() public {
        uint256 sellAmount = 1e18;

        deal(WETH_MAINNET, address(this), 10 * sellAmount);
        IERC20(WETH_MAINNET).approve(address(adapter), 4 * sellAmount);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(adapter).delegatecall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, route.pool, WETH_MAINNET, sellAmount, LDO_MAINNET, 1, route.data
            )
        );

        assertTrue(success);

        uint256 val = abi.decode(data, (uint256));

        assertGe(val, 0);
    }
}
