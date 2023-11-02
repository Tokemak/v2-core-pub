// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IDestinationVaultRegistry, DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";

import {
    TOKE_MAINNET,
    WSTETH_MAINNET,
    RETH_MAINNET,
    STETH_MAINNET,
    WETH_MAINNET,
    FRXETH_MAINNET,
    RANDOM
} from "../utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract SwapRouterTest is Test {
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    SystemRegistry public systemRegistry;
    AccessController private accessController;
    DestinationVaultRegistry public destinationVaultRegistry;
    SwapRouter private swapRouter;

    BalancerV2Swap private balSwapper;
    CurveV1StableSwap private curveSwapper;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 16_728_070);
        vm.selectFork(forkId);

        // setup system
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);

        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        vm.mockCall(
            address(destinationVaultRegistry),
            abi.encodeWithSelector(IDestinationVaultRegistry.isRegistered.selector),
            abi.encode(true)
        );

        // setup swap router
        swapRouter = new SwapRouter(systemRegistry);
        balSwapper = new BalancerV2Swap(address(swapRouter), BALANCER_VAULT);
        curveSwapper = new CurveV1StableSwap(address(swapRouter), WETH_MAINNET);

        // setup input for Balancer 1-hop WETH -> WSTETH
        ISwapRouter.SwapData[] memory balSwapRoute = new ISwapRouter.SwapData[](1);
        balSwapRoute[0] = ISwapRouter.SwapData({
            token: WSTETH_MAINNET,
            pool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            swapper: balSwapper,
            data: abi.encode(0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080)
        });
        swapRouter.setSwapRoute(WETH_MAINNET, balSwapRoute);

        // setup input for Curve 1-hop WETH -> STETH
        ISwapRouter.SwapData[] memory curveOneHopRoute = new ISwapRouter.SwapData[](1);
        curveOneHopRoute[0] = ISwapRouter.SwapData({
            token: STETH_MAINNET,
            pool: 0x828b154032950C8ff7CF8085D841723Db2696056,
            swapper: curveSwapper,
            data: abi.encode(0, 1)
        });
        swapRouter.setSwapRoute(WETH_MAINNET, curveOneHopRoute);

        // setup input for Curve 2-hop WETH -> STETH -> FRXETH
        ISwapRouter.SwapData[] memory curveTwoHopRoute = new ISwapRouter.SwapData[](2);
        curveTwoHopRoute[0] = curveOneHopRoute[0];
        curveTwoHopRoute[1] = ISwapRouter.SwapData({
            token: FRXETH_MAINNET,
            pool: 0x4d9f9D15101EEC665F77210cB999639f760F831E,
            swapper: curveSwapper,
            data: abi.encode(0, 1)
        });
        swapRouter.setSwapRoute(WETH_MAINNET, curveTwoHopRoute);
    }

    function test_setSwapRoute_Reverts_IfAccessDenied() public {
        ISwapRouter.SwapData[] memory swapRoute = new ISwapRouter.SwapData[](0);
        vm.prank(RANDOM);
        vm.expectRevert(IAccessController.AccessDenied.selector);
        swapRouter.setSwapRoute(WETH_MAINNET, swapRoute);
    }

    function test_setSwapRoute_Revert_WhenVerifyNotZeroError() public {
        CurveV1StableSwap swapper = new CurveV1StableSwap(address(swapRouter), WETH_MAINNET);

        ISwapRouter.SwapData[] memory swapRoute = new ISwapRouter.SwapData[](1);

        swapRoute[0] = ISwapRouter.SwapData({
            token: WSTETH_MAINNET,
            pool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            swapper: swapper,
            data: abi.encode(0)
        });
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "assetToken"));
        swapRouter.setSwapRoute(address(0), swapRoute);

        swapRoute[0] = ISwapRouter.SwapData({
            token: address(0),
            pool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            swapper: swapper,
            data: abi.encode(0)
        });
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swap token"));
        swapRouter.setSwapRoute(WETH_MAINNET, swapRoute);

        swapRoute[0] =
            ISwapRouter.SwapData({ token: WSTETH_MAINNET, pool: address(0), swapper: swapper, data: abi.encode(0) });
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swap pool"));
        swapRouter.setSwapRoute(WETH_MAINNET, swapRoute);

        swapRoute[0] = ISwapRouter.SwapData({
            token: WSTETH_MAINNET,
            pool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            swapper: ISyncSwapper(address(0)),
            data: abi.encode(0)
        });
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swap swapper"));
        swapRouter.setSwapRoute(WETH_MAINNET, swapRoute);
    }

    function test_swapForQuote_Revert_IfAccessDenied() public {
        uint256 sellAmount = 1e18;
        address asset = WETH_MAINNET;
        address quote = FRXETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 4 * 1e18);

        vm.mockCall(
            address(destinationVaultRegistry),
            abi.encodeWithSelector(IDestinationVaultRegistry.isRegistered.selector),
            abi.encode(false)
        );

        vm.expectRevert(Errors.AccessDenied.selector);
        swapRouter.swapForQuote(asset, sellAmount, quote, 1);
    }

    function test_swapForQuote_Revert_IfZeroAmount() public {
        address asset = WETH_MAINNET;
        address quote = STETH_MAINNET;

        vm.expectRevert(Errors.ZeroAmount.selector);
        swapRouter.swapForQuote(asset, 0, quote, 1);
    }

    function test_swapForQuote_Revert_IfSameTokens() public {
        address asset = WETH_MAINNET;

        vm.expectRevert(Errors.InvalidParams.selector);
        swapRouter.swapForQuote(asset, 1, asset, 1);
    }

    function test_swapForQuote_Revert_IfSwapRouteLookupFailed() public {
        address asset = RANDOM;
        address quote = STETH_MAINNET;
        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 10 * 1e18);

        vm.expectRevert(ISwapRouter.SwapRouteLookupFailed.selector);
        swapRouter.swapForQuote(asset, 1, quote, 1);
    }

    function test_swapForQuote_Revert_IfMaxSlippageExceeded() public {
        uint256 sellAmount = 1e18;
        address asset = WETH_MAINNET;
        address quote = FRXETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 4 * 1e18);

        vm.mockCall(address(curveSwapper), abi.encodeWithSelector(ISyncSwapper.swap.selector), abi.encode(0));

        vm.expectRevert(ISwapRouter.MaxSlippageExceeded.selector);
        swapRouter.swapForQuote(asset, sellAmount, quote, 1);
    }

    function test_Success() public {
        uint256 sellAmount = 1e18;
        address asset = WETH_MAINNET;
        address quote = FRXETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 4 * 1e18);

        uint256 val = swapRouter.swapForQuote(asset, sellAmount, quote, 1);
        assertGe(val, 0);
    }

    function test_swap_CurveOneHop() public {
        uint256 sellAmount = 1e18;
        // swap STETH with Curve pool
        address asset = WETH_MAINNET;
        address quote = STETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 4 * 1e18);
        // 1-hop swap: WETH -> STETH
        uint256 val = swapRouter.swapForQuote(asset, sellAmount, quote, 1);
        assertGe(val, 0);
    }

    function test_swap_CurveTwoHop() public {
        uint256 sellAmount = 1e18;
        // swap STETH with Curve pool
        address asset = WETH_MAINNET;
        // 2-hop swap: WETH -> STETH -> FRXETH
        address quote = FRXETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 4 * 1e18);

        uint256 val = swapRouter.swapForQuote(asset, sellAmount, quote, 1);
        assertGe(val, 0);
    }

    function test_swap_Balancer() public {
        uint256 sellAmount = 1e18;
        // swap WSTETH with Balancer pool
        address asset = WETH_MAINNET;
        address quote = WSTETH_MAINNET;

        deal(WETH_MAINNET, address(this), 10 * 1e18);
        IERC20(WETH_MAINNET).approve(address(swapRouter), 2 * 1e18);

        uint256 val = swapRouter.swapForQuote(asset, sellAmount, quote, 1);
        assertGe(val, 0);
    }
}
