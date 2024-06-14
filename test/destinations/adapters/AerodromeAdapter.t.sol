// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
// import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IRouter } from "src/interfaces/external/aerodrome/IRouter.sol";
import { AerodromeAdapter } from "src/destinations/adapters/AerodromeAdapter.sol";
import { Errors } from "src/utils/Errors.sol";
import { AERODROME_SWAP_ROUTER_BASE, USDC_BASE, DAI_BASE, WETH9_BASE, RANDOM } from "test/utils/Addresses.sol";

contract AerodromeAdapterTest is Test {
    uint256 public baseFork;

    ///@notice Auto-wrap on receive as system operates with WETH
    receive() external payable {
        // weth.deposit{ value: msg.value }();
    }

    function setUp() public {
        string memory endpoint = vm.envString("BASE_MAINNET_RPC_URL");
        baseFork = vm.createFork(endpoint, 14_406_720);
        vm.selectFork(baseFork);
        assertEq(vm.activeFork(), baseFork);
    }

    /**
     * @notice Deploy liquidity to Aerodrome pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param router Balancer Vault contract
     * @param tokenA Addresse of tokenA in the pool
     * @param tokenB Addresse of tokenB in the pool
     * @param stable A flag that indicates pool type
     * @param desiredTokenAmountA Desired Amount of tokenA to deposit
     * @param desiredTokenAmountB Desired Amount of tokenB to deposit
     */
    function _addLiquidity(
        address router,
        address tokenA,
        address tokenB,
        bool stable,
        uint256 desiredTokenAmountA,
        uint256 desiredTokenAmountB
    ) private returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        Errors.verifyNotZero(router, "router");
        Errors.verifyNotZero(tokenA, "tokenA");
        Errors.verifyNotZero(tokenB, "tokenB");
        Errors.verifyNotZero(desiredTokenAmountA, "desiredTokenAmountA");
        Errors.verifyNotZero(desiredTokenAmountB, "desiredTokenAmountB");
        IERC20(tokenA).approve(router, desiredTokenAmountA);
        IERC20(tokenB).approve(router, desiredTokenAmountB);
        (amountA, amountB, liquidity) = IRouter(router).addLiquidity(
            tokenA, tokenB, stable, desiredTokenAmountA, desiredTokenAmountB, 1, 1, address(this), block.timestamp
        );
    }

    function test_validate_RevertIfZeroRouter() public {
        address[] memory tokens = new address[](2);

        tokens[0] = DAI_BASE;
        tokens[1] = USDC_BASE;

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 1;
        amounts[1] = 1;

        uint256 maxLpBurnAmount = 100;
        bool stable = true;
        address pool = RANDOM;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: address(0),
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "router"));
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);
    }

    function test_validate_RevertIfZeroLpBurnAmount() public {
        address[] memory tokens = new address[](2);

        tokens[0] = DAI_BASE;
        tokens[1] = USDC_BASE;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        address router = AERODROME_SWAP_ROUTER_BASE;

        uint256 maxLpBurnAmount = 0;
        bool stable = true;
        address pool = RANDOM;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: router,
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxLpBurnAmount"));
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);
    }

    function test_validate_RevertIfZeroToken() public {
        address[] memory tokens = new address[](2);

        tokens[0] = address(0);
        tokens[1] = USDC_BASE;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        address router = AERODROME_SWAP_ROUTER_BASE;
        uint256 maxLpBurnAmount = 100;
        bool stable = true;
        address pool = RANDOM;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: router,
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokens[0]"));
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);

        tokens[0] = DAI_BASE;
        tokens[1] = address(0);

        removeLiquidityParams.tokens = tokens;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokens[1]"));
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);
    }

    function test_validate_RevertIfIncorrectAmountsLength() public {
        address[] memory tokens = new address[](2);

        tokens[0] = DAI_BASE;
        tokens[1] = USDC_BASE;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        address router = AERODROME_SWAP_ROUTER_BASE;
        uint256 maxLpBurnAmount = 100;
        bool stable = true;
        address pool = RANDOM;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: router,
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amounts.length"));
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);
    }

    function test_removeLiquidityStable() public {
        //Test with DAI , USDC
        address tokenA = DAI_BASE;
        address tokenB = USDC_BASE;
        uint256 depAmountUSDC = 100 * 1e6;
        uint256 depAmountDAI = 100 * 1e18;

        deal(DAI_BASE, address(this), 2 * depAmountDAI);
        vm.startPrank(address(0xd5c41FD4a31Eaaf5559FfCC60Ec051fcB8eCC375));
        IERC20(USDC_BASE).transfer(address(this), 2 * depAmountUSDC);
        vm.stopPrank();

        address[] memory tokens = new address[](2);

        tokens[0] = DAI_BASE;
        tokens[1] = USDC_BASE;
        address router = AERODROME_SWAP_ROUTER_BASE;
        address factory = IRouter(router).defaultFactory();
        address pool = IRouter(router).poolFor(tokenA, tokenB, true, factory);

        (,, uint256 liquidity) = _addLiquidity(router, tokenA, tokenB, true, depAmountDAI, depAmountUSDC);

        uint256 daiBefore = IERC20(DAI_BASE).balanceOf(address(this));
        uint256 usdcBefore = IERC20(USDC_BASE).balanceOf(address(this));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        uint256 maxLpBurnAmount = liquidity;
        bool stable = true;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: router,
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);

        uint256 daiAfter = IERC20(DAI_BASE).balanceOf(address(this));
        uint256 usdcAfter = IERC20(USDC_BASE).balanceOf(address(this));

        assertEq(daiAfter - daiBefore, actualAmounts[0]);
        assertEq(usdcAfter - usdcBefore, actualAmounts[1]);
    }

    function test_removeLiquidityNonStable() public {
        //Test with DAI , USDC
        address tokenA = WETH9_BASE;
        address tokenB = USDC_BASE;
        uint256 depAmountUSDC = 100 * 1e6;
        uint256 depAmountWETH9 = 100 * 1e18;

        deal(WETH9_BASE, address(this), 2 * depAmountWETH9);
        vm.startPrank(address(0xd5c41FD4a31Eaaf5559FfCC60Ec051fcB8eCC375));
        IERC20(USDC_BASE).transfer(address(this), 2 * depAmountUSDC);
        vm.stopPrank();

        address[] memory tokens = new address[](2);

        tokens[0] = WETH9_BASE;
        tokens[1] = USDC_BASE;

        address router = AERODROME_SWAP_ROUTER_BASE;
        address factory = IRouter(router).defaultFactory();
        address pool = IRouter(router).poolFor(tokenA, tokenB, false, factory);

        (,, uint256 liquidity) = _addLiquidity(router, tokenA, tokenB, false, depAmountWETH9, depAmountUSDC);

        uint256 weth9Before = IERC20(WETH9_BASE).balanceOf(address(this));
        uint256 usdcBefore = IERC20(USDC_BASE).balanceOf(address(this));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        uint256 maxLpBurnAmount = liquidity;
        bool stable = false;

        AerodromeAdapter.AerodromeRemoveLiquidityParams memory removeLiquidityParams = AerodromeAdapter
            .AerodromeRemoveLiquidityParams({
            router: router,
            tokens: tokens,
            amounts: amounts,
            pool: pool,
            stable: stable,
            maxLpBurnAmount: maxLpBurnAmount
        });

        uint256[] memory actualAmounts = new uint256[](2);
        actualAmounts = AerodromeAdapter.removeLiquidity(removeLiquidityParams);

        uint256 weth9After = IERC20(WETH9_BASE).balanceOf(address(this));
        uint256 usdcAfter = IERC20(USDC_BASE).balanceOf(address(this));

        assertEq(weth9After - weth9Before, actualAmounts[0]);
        assertEq(usdcAfter - usdcBefore, actualAmounts[1]);
    }
}
