// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
// solhint-disable not-rely-on-time
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IRouter } from "src/interfaces/external/velodrome/IRouter.sol";
import { VelodromeAdapter } from "src/destinations/adapters/VelodromeAdapter.sol";
import { TestableVM } from "src/solver/test/TestableVM.sol";
import { SolverCaller } from "src/solver/test/SolverCaller.sol";
import { ReadPlan } from "test/utils/ReadPlan.sol";
import {
    WSTETH_OPTIMISM, WETH9_OPTIMISM, RETH_OPTIMISM, SETH_OPTIMISM, FRXETH_OPTIMISM
} from "test/utils/Addresses.sol";

struct VelodromeExtraParams {
    address tokenA;
    address tokenB;
    bool stable;
    uint256 amountAMin;
    uint256 amountBMin;
    uint256 deadline;
}

// TODO: figure out the testing approach with Adapter being now a library
// contract VelodromeAdapterWrapper is SolverCaller, VelodromeAdapter {
//     constructor(address _rooter) VelodromeAdapter(_rooter) { }
// }

contract VelodromeAdapterTest is Test {
    // VelodromeAdapterWrapper private adapter;
    IRouter private router;
    TestableVM public solver;

    function setUp() public {
        string memory endpoint = vm.envString("OPTIMISM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 86_937_163);
        vm.selectFork(forkId);

        router = IRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);

        // adapter = new VelodromeAdapterWrapper(
        //     address(router)
        // );
        solver = new TestableVM();
    }

    // Test revert on addLiquidity
    function testRevertOnAddLiquidityWhenRouterIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "router"));
        VelodromeAdapter.addLiquidity(address(0), amounts, minLpMintAmount, extraParams);
    }

    function testRevertOnAddLiquidityWhenAmountsIsInvalidLength() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amounts.length"));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    function testRevertOnAddLiquidityWhenAddLiquidityIsEmptyValues() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0 * 1e18;
        amounts[1] = 0 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        vm.expectRevert(abi.encodeWithSelector(LibAdapter.NoNonZeroAmountProvided.selector));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    function testRevertOnAddLiquidityWhenMinLpMintAmountIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 0;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "minLpMintAmount"));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    // Test extra params
    function testRevertOnAddLiquidityWhenTokenAIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams =
            abi.encode(VelodromeExtraParams(address(0), WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "extraParams.tokenA"));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    function testRevertOnAddLiquidityWhenTokenBIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams =
            abi.encode(VelodromeExtraParams(WSTETH_OPTIMISM, address(0), isStablePool, 1, 1, block.timestamp + 10_000));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "extraParams.tokenB"));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    function testRevertOnAddLiquidityWhenDeadlineIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams =
            abi.encode(VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, 0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "extraParams.deadline"));
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);
    }

    // Test revert on removeLiquidity
    function testRevertOnRemoveLiquidityWhenRouterIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "router"));
        VelodromeAdapter.removeLiquidity(address(0), withdrawAmounts, preLpBalance, extraParams);
    }

    function testRevertOnRemoveLiquidityWhenAmountsIsInvalidLength() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 3 * 1e18;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amounts.length"));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);
    }

    function testRevertOnAddLiquidityWhenRemoveLiquidityIsEmptyValues() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0 * 1e18;
        withdrawAmounts[1] = 0 * 1e18;

        vm.expectRevert(abi.encodeWithSelector(LibAdapter.NoNonZeroAmountProvided.selector));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);
    }

    function testRevertOnRemoveLiquidityWhenMaxLpBurnAmountIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxLpBurnAmount"));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, 0, extraParams);
    }

    // Test extra params
    function testRevertOnRemoveLiquidityWhenTokenAIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;

        extraParams =
            abi.encode(VelodromeExtraParams(address(0), WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "extraParams.tokenA"));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);
    }

    function testRevertOnRemoveLiquidityWhenTokenBIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;

        extraParams =
            abi.encode(VelodromeExtraParams(WSTETH_OPTIMISM, address(0), isStablePool, 1, 1, block.timestamp + 10_000));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "extraParams.tokenB"));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);
    }

    function testRevertOnRemoveLiquidityWhenDeadlineIsZero() public {
        bool isStablePool = true;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );

        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;

        extraParams = abi.encode(VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, 0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "extraParams.deadline"));
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);
    }

    // WETH/sETH
    function testAddLiquidityWethSeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WETH9_OPTIMISM), address(this), 3 * 1e18);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
        vm.startPrank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
        IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);
        vm.stopPrank();

        uint256 preBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 afterBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        uint256 balanceDiff1 = preBalance1 - afterBalance1;
        assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

        uint256 balanceDiff2 = preBalance2 - afterBalance2;
        assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);
        assertTrue(afterLpBalance > preLpBalance);
    }

    // WETH/sETH
    function testRemoveLiquidityWethSeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WETH9_OPTIMISM), address(this), 3 * 1e18);
        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 preBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);

        uint256 afterBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // wstETH/sETH
    function testAddLiquidityWstEthSeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, SETH_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 3 * 1e18);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
        vm.startPrank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
        IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);
        vm.stopPrank();

        uint256 preBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, SETH_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 afterBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        uint256 balanceDiff1 = preBalance1 - afterBalance1;
        assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

        uint256 balanceDiff2 = preBalance2 - afterBalance2;
        assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);

        assertTrue(afterLpBalance > preLpBalance);
    }

    // wstETH/sETH 0xB343dae0E7fe28c16EC5dCa64cB0C1ac5F4690AC
    function testRemoveLiquidityWstEthSeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, SETH_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 3 * 1e18);
        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, SETH_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 preBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);

        uint256 afterBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // wstETH/WETH
    function testAddLiquidityWstEthWeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 afterBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        uint256 balanceDiff1 = preBalance1 - afterBalance1;
        assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

        uint256 balanceDiff2 = preBalance2 - afterBalance2;
        assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);

        assertTrue(afterLpBalance > preLpBalance);
    }

    // wstETH/WETH
    function testRemoveLiquidityWstEthWeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(WSTETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 preBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);

        uint256 afterBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // frxETH/WETH
    function testAddLiquidityFrxEthWeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(FRXETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(FRXETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 preBalance1 = IERC20(FRXETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(FRXETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 afterBalance1 = IERC20(FRXETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        uint256 balanceDiff1 = preBalance1 - afterBalance1;
        assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

        uint256 balanceDiff2 = preBalance2 - afterBalance2;
        assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);

        assertTrue(afterLpBalance > preLpBalance);
    }

    // frxETH/WETH
    function testRemoveLiquidityFrxEthWeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(FRXETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(FRXETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(FRXETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 preBalance1 = IERC20(FRXETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);

        uint256 afterBalance1 = IERC20(FRXETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // WETH/rETH
    function testAddLiquidityWethReth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(RETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(RETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 preBalance1 = IERC20(RETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(RETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 afterBalance1 = IERC20(RETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        uint256 balanceDiff1 = preBalance1 - afterBalance1;
        assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

        uint256 balanceDiff2 = preBalance2 - afterBalance2;
        assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);

        assertTrue(afterLpBalance > preLpBalance);
    }

    // WETH/rETH
    function testRemoveLiquidityWethReth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(RETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 7 * 1e18;
        amounts[1] = 7 * 1e18;

        deal(address(RETH_OPTIMISM), address(this), 10 * 1e18);
        deal(address(WETH9_OPTIMISM), address(this), 10 * 1e18);

        uint256 minLpMintAmount = 1;

        bytes memory extraParams = abi.encode(
            VelodromeExtraParams(RETH_OPTIMISM, WETH9_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
        );
        VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

        uint256 preBalance1 = IERC20(RETH_OPTIMISM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 3 * 1e18;
        withdrawAmounts[1] = 3 * 1e18;
        VelodromeAdapter.removeLiquidity(address(router), withdrawAmounts, preLpBalance, extraParams);

        uint256 afterBalance1 = IERC20(RETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // TODO: figure out the testing approach with Adapter being now a library
    /// @dev This is an integration test for the Solver project. More information is available in the README.
    // function testAddLiquidityUsingSolver() public {
    //     bool isStablePool = true;

    //     IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool));

    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = 1.5 * 1e18;
    //     amounts[1] = 1.5 * 1e18;

    //     deal(address(WETH9_OPTIMISM), address(this), 3 * 1e18);

    //     // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
    //     address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
    //     vm.startPrank(sethWhale);
    //     IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
    //     IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);
    //     vm.stopPrank();

    //     uint256 preBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
    //     uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
    //     uint256 preLpBalance = lpToken.balanceOf(address(this));

    //     (bytes32[] memory commands, bytes[] memory elements) =
    //         ReadPlan.getPayload(vm, "velodrome-add-liquidity.json", address(this));
    //     adapter.execute(address(solver), commands, elements);

    //     uint256 afterBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
    //     uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
    //     uint256 afterLpBalance = lpToken.balanceOf(address(this));

    //     uint256 balanceDiff1 = preBalance1 - afterBalance1;
    //     assertTrue(balanceDiff1 > 0 && balanceDiff1 <= amounts[0]);

    //     uint256 balanceDiff2 = preBalance2 - afterBalance2;
    //     assertTrue(balanceDiff2 > 0 && balanceDiff2 <= amounts[1]);
    //     assertTrue(afterLpBalance > preLpBalance);
    // }

    /// @dev This is an integration test for the Solver project. More information is available in the README.
    // function testRemoveLiquidityUsingSolver() public {
    //     bool isStablePool = true;

    //     IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool));

    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = 1.5 * 1e18;
    //     amounts[1] = 1.5 * 1e18;

    //     deal(address(WETH9_OPTIMISM), address(this), 3 * 1e18);
    //     // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
    //     address sethWhale = 0x9912a94725271600590BeB0815Ca96fA0065eA27;
    //     vm.prank(sethWhale);
    //     IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
    //     vm.prank(sethWhale);
    //     IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);

    //     uint256 minLpMintAmount = 1;

    //     bytes memory extraParams = abi.encode(
    //         VelodromeExtraParams(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool, 1, 1, block.timestamp + 10_000)
    //     );
    //     VelodromeAdapter.addLiquidity(address(router), amounts, minLpMintAmount, extraParams);

    //     uint256 preBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
    //     uint256 preBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
    //     uint256 preLpBalance = lpToken.balanceOf(address(this));

    //     uint256[] memory withdrawAmounts = new uint256[](2);
    //     withdrawAmounts[0] = 1 * 1e18;
    //     withdrawAmounts[1] = 1 * 1e18;

    //     (bytes32[] memory commands, bytes[] memory elements) =
    //         ReadPlan.getPayload(vm, "velodrome-remove-liquidity.json", address(this));
    //     adapter.execute(address(solver), commands, elements);

    //     uint256 afterBalance1 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
    //     uint256 afterBalance2 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
    //     uint256 afterLpBalance = lpToken.balanceOf(address(this));

    //     assert(afterBalance1 > preBalance1);
    //     assert(afterBalance2 > preBalance2);
    //     assert(afterLpBalance < preLpBalance);
    // }
}
