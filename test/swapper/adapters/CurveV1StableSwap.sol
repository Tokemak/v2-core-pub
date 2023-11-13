// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable var-name-mixedcase
// solhint-disable avoid-low-level-calls

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { ICurveV1StableSwap } from "src/interfaces/external/curve/ICurveV1StableSwap.sol";

import { STETH_MAINNET, WETH_MAINNET, RANDOM, CURVE_ETH, STETH_WHALE } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract CurveV1StableSwapTest is Test {
    uint256 public sellAmount = 1e18;

    CurveV1StableSwap private adapter;

    ISwapRouter.SwapData private routeWeth;
    ISwapRouter.SwapData private routeEth; // To test edge cases with receiving Eth.

    uint256 public forkIdBlock_16_728_070;
    uint256 public forkIdBlock_18_392_259;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        forkIdBlock_16_728_070 = vm.createFork(endpoint, 16_728_070);
        forkIdBlock_18_392_259 = vm.createFork(endpoint, 18_392_259);

        vm.selectFork(forkIdBlock_16_728_070);

        adapter = new CurveV1StableSwap(address(this), WETH_MAINNET);

        vm.makePersistent(address(adapter));

        // route WETH_MAINNET -> STETH_MAINNET
        routeWeth = ISwapRouter.SwapData({
            token: STETH_MAINNET,
            pool: 0x828b154032950C8ff7CF8085D841723Db2696056,
            swapper: adapter,
            data: abi.encode(0, 1)
        });

        // route STETH_MAINNET -> ETH
        routeEth = ISwapRouter.SwapData({
            token: CURVE_ETH,
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            swapper: adapter,
            data: abi.encode(1, 0)
        });
    }

    function test_validate_Revert_IfFromAddressMismatch() public {
        // pretend that the pool doesn't have WETH_MAINNET
        vm.mockCall(routeWeth.pool, abi.encodeWithSelector(ICurveV1StableSwap.coins.selector, 0), abi.encode(RANDOM));
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "fromAddress"));
        adapter.validate(WETH_MAINNET, routeWeth);
    }

    function test_validate_Revert_IfToAddressMismatch() public {
        // pretend that the pool doesn't have STETH_MAINNET
        vm.mockCall(routeWeth.pool, abi.encodeWithSelector(ICurveV1StableSwap.coins.selector, 1), abi.encode(RANDOM));
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "toAddress"));
        adapter.validate(WETH_MAINNET, routeWeth);
    }

    function test_validate_Works() public view {
        adapter.validate(WETH_MAINNET, routeWeth);
    }

    function test_swap_Works() public {
        deal(WETH_MAINNET, address(this), 10 * sellAmount);
        IERC20(WETH_MAINNET).approve(address(adapter), 4 * sellAmount);

        (bool success, bytes memory data) = address(adapter).delegatecall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, routeWeth.pool, WETH_MAINNET, sellAmount, STETH_MAINNET, 1, routeWeth.data
            )
        );

        assertTrue(success);

        uint256 val = abi.decode(data, (uint256));

        assertGe(val, 0);
    }

    function test_swap_DoesNotConvertEth_WhenBuyTokenIsNotEthOrWeth() external {
        // More recent fork for STETH_WHALE.
        vm.selectFork(forkIdBlock_18_392_259);

        // Mock whale, send funds to use.
        vm.prank(STETH_WHALE);
        IERC20(STETH_MAINNET).transfer(address(this), 10 * sellAmount);
        IERC20(STETH_MAINNET).approve(address(adapter), 10 * sellAmount);

        // Make sure that weth balance is 0 before swap.
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), 0);

        // Snapshot balance before.
        uint256 ethBalanceBefore = address(this).balance;

        // Make sure that address(this).balance > 0 before swap.  Neccessary to make sure if statement
        //      operating correctly.
        assertGt(ethBalanceBefore, 0);

        // Delegatecall swapper with random address.  This ensures that we do not swap to weth.
        (bool success,) = address(adapter).delegatecall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, routeEth.pool, STETH_MAINNET, sellAmount, vm.addr(1), 1, routeEth.data
            )
        );

        // Assert call passed.
        assertTrue(success);

        // Make sure we didn't swap for weth
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), 0);

        // Snapshot balance after.
        uint256 ethBalanceAfter = address(this).balance;

        // Make sure Eth balance increases.
        assertGt(ethBalanceAfter, ethBalanceBefore);
    }

    // Testing for eth swap with extra Eth in swap router.
    function test_swap_UpdatesAmountProperlyWhen_SwappingForEth() external {
        vm.selectFork(forkIdBlock_18_392_259);

        // stEth - eth pool.
        ICurveV1StableSwap pool = ICurveV1StableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

        // Mock whale, send funds.
        vm.prank(STETH_WHALE);
        IERC20(STETH_MAINNET).transfer(address(this), 10 * sellAmount);
        IERC20(STETH_MAINNET).approve(address(adapter), 10 * sellAmount); // Approve adapter.
        IERC20(STETH_MAINNET).approve(address(pool), 10 * sellAmount); // Approve pool.

        /**
         * Goal here is to make a swap on the pool with the exact same amount that we will be swapping with
         *      in the adapter, then reset the EVM to the state it was before the original swap,
         *      so that we can have an exact amount of Eth back to compare to.  Steps:
         *
         *      - Snapshot EVM.
         *      - Perform swap, save amount of Eth returned.
         *      - Revert EVM.
         *      - Perform swap with adapter.
         */
        uint256 snapshot = vm.snapshot();
        uint256 exchangeAmount = pool.exchange(1, 0, sellAmount, 1);
        vm.revertTo(snapshot);

        // Make sure that weth balance is 0 before swap.
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), 0);

        // Transfer some Eth out, snapshot.
        payable(vm.addr(1)).transfer(address(this).balance - 1000);
        uint256 ethBalanceBefore = address(this).balance;

        // Make sure that there is some dust for swapper to pick up.
        assertGt(ethBalanceBefore, 0);

        // Delegatecall swapper with Eth placeholder address as buyToken
        (bool success,) = address(adapter).delegatecall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, routeEth.pool, STETH_MAINNET, sellAmount, CURVE_ETH, 1, routeEth.data
            )
        );

        // Make sure call passed.
        assertTrue(success);

        // Make sure weth balance increased.
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), exchangeAmount + ethBalanceBefore);
    }

    // Testing for weth swap with extra Eth laying in swap router (address(this) in this case)
    function test_swap_UpdatesAmountProperlyWhen_SwappingForWeth() external {
        vm.selectFork(forkIdBlock_18_392_259);

        // stEth - weth pool.
        ICurveV1StableSwap pool = ICurveV1StableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);

        // Mock whale, send funds.
        vm.prank(STETH_WHALE);
        IERC20(STETH_MAINNET).transfer(address(this), 10 * sellAmount);
        IERC20(STETH_MAINNET).approve(address(adapter), 10 * sellAmount); // Approve adapter.
        IERC20(STETH_MAINNET).approve(address(pool), 10 * sellAmount); // Approve pool.

        /**
         * Goal here is to make a swap on the pool with the exact same amount that we will be swapping with
         *      in the adapter, then reset the EVM to the state it was before the original swap,
         *      so that we can have an exact amount of Eth back to compare to.  Steps:
         *
         *      - Snapshot EVM.
         *      - Perform swap, save amount of Eth returned.
         *      - Revert EVM.
         *      - Perform swap with adapter.
         */
        uint256 snapshot = vm.snapshot();
        uint256 exchangeAmount = pool.exchange(1, 0, sellAmount, 1);
        vm.revertTo(snapshot);

        // Assert that weth balance is 0 before swapping.
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), 0);

        // Transfer some Eth out, snapshot amount that is left.
        payable(vm.addr(1)).transfer(address(this).balance - 1000);
        uint256 ethBalanceBefore = address(this).balance;

        // Just need Eth balance to be > 0 to test properly.
        assertGt(ethBalanceBefore, 0);

        // Delegatecall swapper with weth address as buyToken.
        (bool success,) = address(adapter).delegatecall(
            abi.encodeWithSelector(
                ISyncSwapper.swap.selector, address(pool), STETH_MAINNET, sellAmount, WETH_MAINNET, 1, abi.encode(1, 0)
            )
        );

        // Assert that call passed.
        assertTrue(success);

        // Make sure that weth balance is what we expect, weth gained from swap + eth balance
        //      of this address before swap.
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), exchangeAmount + ethBalanceBefore);
    }

    receive() external payable { }
}
