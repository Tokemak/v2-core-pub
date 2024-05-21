// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { IRouter } from "src/interfaces/external/aerodrome/IRouter.sol";

import { AerodromeSwap } from "src/swapper/adapters/AerodromeSwap.sol";

import {
    USDC_BASE,
    RANDOM,
    DAI_BASE,
    WETH9_BASE,
    AERODROME_SWAP_ROUTER_BASE,
    AERO_BASE,
    USDBC_BASE
} from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
// solhint-disable max-line-length
contract AerodromeSwapTest is Test {
    using Address for address;

    AerodromeSwap private adapter;

    IRouter private aerodromeRouter;

    ISwapRouter.SwapData private route;
    address private daiUsdcPool;

    //Check BASE_MAINNET
    function setUp() public {
        string memory endpoint = vm.envString("BASE_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 14_406_720);

        vm.selectFork(forkId);

        adapter = new AerodromeSwap(AERODROME_SWAP_ROUTER_BASE, address(this));
        aerodromeRouter = IRouter(AERODROME_SWAP_ROUTER_BASE);

        //route DAI_BASE ---> USDC_BASE

        IRouter.Route[] memory aerodromeRoutes = new IRouter.Route[](1);

        aerodromeRoutes[0] =
            IRouter.Route({ from: DAI_BASE, to: USDC_BASE, stable: true, factory: aerodromeRouter.defaultFactory() });

        daiUsdcPool = aerodromeRouter.poolFor(
            aerodromeRoutes[0].from, aerodromeRoutes[0].to, aerodromeRoutes[0].stable, aerodromeRoutes[0].factory
        );

        route = ISwapRouter.SwapData({
            token: USDC_BASE,
            pool: address(aerodromeRouter),
            swapper: adapter,
            data: abi.encode(aerodromeRoutes)
        });
    }

    function test_validate_Revert_IfFromAddressMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "fromToken"));
        adapter.validate(RANDOM, route);
    }

    function test_validate_Revert_IfToAddressMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "toToken"));
        route.token = RANDOM;
        adapter.validate(DAI_BASE, route);
    }

    function test_validate_Revert_IfRouterAddressMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "router"));
        route.pool = RANDOM;
        adapter.validate(DAI_BASE, route);
    }

    function test_validate() public view {
        adapter.validate(DAI_BASE, route);
    }

    function test_validate_ManyRoutes() public {
        IRouter.Route[] memory aerodromeRoutes = new IRouter.Route[](2);

        aerodromeRoutes[0] =
            IRouter.Route({ from: WETH9_BASE, to: USDC_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        aerodromeRoutes[1] =
            IRouter.Route({ from: USDBC_BASE, to: AERO_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        route.token = AERO_BASE;
        route.data = abi.encode(aerodromeRoutes);
        vm.expectRevert(abi.encodeWithSelector(ISyncSwapper.DataMismatch.selector, "internalRoute"));
        adapter.validate(WETH9_BASE, route);
    }

    function test_validate_Revert_IfWrongInternaRoute() public {
        IRouter.Route[] memory aerodromeRoutes = new IRouter.Route[](2);

        aerodromeRoutes[0] =
            IRouter.Route({ from: WETH9_BASE, to: USDC_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        aerodromeRoutes[1] =
            IRouter.Route({ from: USDC_BASE, to: AERO_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        route.token = AERO_BASE;
        route.data = abi.encode(aerodromeRoutes);
        adapter.validate(WETH9_BASE, route);
    }

    function test_swap_Works() public {
        //test from WETH to AERO
        uint256 sellAmount = 1e18;

        deal(WETH9_BASE, address(this), 10 * sellAmount);
        IERC20(WETH9_BASE).approve(address(adapter), 4 * sellAmount);

        // get balance of AERO_BASE before swap
        uint256 aeroBalanceBefore = IERC20(AERO_BASE).balanceOf(address(this));

        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] =
            IRouter.Route({ from: WETH9_BASE, to: USDC_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        routes[1] =
            IRouter.Route({ from: USDC_BASE, to: AERO_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        bytes memory data = address(adapter).functionDelegateCall(
            abi.encodeCall(
                ISyncSwapper.swap, (address(aerodromeRouter), WETH9_BASE, sellAmount, AERO_BASE, 1, abi.encode(routes))
            )
        );

        // get balance of WETH_MAINNET after swap
        uint256 aeroBalanceAfter = IERC20(AERO_BASE).balanceOf(address(this));
        uint256 val = abi.decode(data, (uint256));

        assertGt(aeroBalanceAfter, aeroBalanceBefore);

        // check that the amount of WETH received is equal to the amount returned by the swap function
        assertEq(val, aeroBalanceAfter - aeroBalanceBefore);
    }

    function test_swap_SingleWorks() public {
        uint256 sellAmount = 1e18;

        deal(DAI_BASE, address(this), 10 * sellAmount);
        IERC20(DAI_BASE).approve(address(adapter), 4 * sellAmount);

        // get balance of WETH_MAINNET before swap
        uint256 usdcBalanceBefore = IERC20(USDC_BASE).balanceOf(address(this));

        bytes memory data = address(adapter).functionDelegateCall(
            abi.encodeCall(
                ISyncSwapper.swap, (address(aerodromeRouter), DAI_BASE, sellAmount, USDC_BASE, 1, route.data)
            )
        );

        // get balance of WETH_MAINNET after swap
        uint256 usdcBalanceAfter = IERC20(USDC_BASE).balanceOf(address(this));
        uint256 val = abi.decode(data, (uint256));

        assertGt(usdcBalanceAfter, usdcBalanceBefore);

        // check that the amount of WETH received is equal to the amount returned by the swap function
        assertEq(val, usdcBalanceAfter - usdcBalanceBefore);
    }

    function test_swap_many_Works() public {
        //test from WETH to AERO
        uint256 sellAmount = 1e18;

        deal(WETH9_BASE, address(this), 10 * sellAmount);
        IERC20(WETH9_BASE).approve(address(adapter), 4 * sellAmount);

        // get balance of AERO_BASE before swap
        uint256 aeroBalanceBefore = IERC20(AERO_BASE).balanceOf(address(this));

        IRouter.Route[] memory routes = new IRouter.Route[](4);
        routes[0] =
            IRouter.Route({ from: WETH9_BASE, to: USDC_BASE, stable: false, factory: aerodromeRouter.defaultFactory() });

        routes[1] =
            IRouter.Route({ from: USDC_BASE, to: DAI_BASE, stable: true, factory: aerodromeRouter.defaultFactory() });

        routes[2] =
            IRouter.Route({ from: DAI_BASE, to: USDBC_BASE, stable: true, factory: aerodromeRouter.defaultFactory() });
        routes[3] =
            IRouter.Route({ from: USDBC_BASE, to: AERO_BASE, stable: true, factory: aerodromeRouter.defaultFactory() });

        bytes memory data = address(adapter).functionDelegateCall(
            abi.encodeCall(
                ISyncSwapper.swap, (address(aerodromeRouter), WETH9_BASE, sellAmount, AERO_BASE, 1, abi.encode(routes))
            )
        );

        // get balance of WETH_MAINNET after swap
        uint256 aeroBalanceAfter = IERC20(AERO_BASE).balanceOf(address(this));
        uint256 val = abi.decode(data, (uint256));

        assertGt(aeroBalanceAfter, aeroBalanceBefore);

        // check that the amount of WETH received is equal to the amount returned by the swap function
        assertEq(val, aeroBalanceAfter - aeroBalanceBefore);
    }
}
