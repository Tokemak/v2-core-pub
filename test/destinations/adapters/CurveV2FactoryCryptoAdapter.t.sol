// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { CurveV2FactoryCryptoAdapter } from "src/destinations/adapters/CurveV2FactoryCryptoAdapter.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IDestinationAdapter } from "src/interfaces/destinations/IDestinationAdapter.sol";
import { ICryptoSwapPool, IPool } from "src/interfaces/external/curve/ICryptoSwapPool.sol";
import {
    PRANK_ADDRESS,
    RANDOM,
    WETH_MAINNET,
    RETH_MAINNET,
    SETH_MAINNET,
    FRXETH_MAINNET,
    STETH_MAINNET,
    WETH9_OPTIMISM,
    SETH_OPTIMISM,
    WSTETH_OPTIMISM,
    WSTETH_ARBITRUM,
    WETH_ARBITRUM
} from "test/utils/Addresses.sol";

import { TestableVM } from "src/solver/test/TestableVM.sol";
import { SolverCaller } from "src/solver/test/SolverCaller.sol";
import { ReadPlan } from "test/utils/ReadPlan.sol";

contract CurveV2FactoryCryptoAdapterTest is Test {
    uint256 public mainnetFork;
    TestableVM public solver;

    IWETH9 private weth;

    ///@notice Auto-wrap on receive as system operates with WETH
    receive() external payable {
        // weth.deposit{ value: msg.value }();
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_000_000);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        solver = new TestableVM();
        weth = IWETH9(WETH_MAINNET);
    }

    function forkArbitrum() private {
        string memory endpoint = vm.envString("ARBITRUM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint);
        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        weth = IWETH9(WETH_ARBITRUM);
    }

    function forkOptimism() private {
        string memory endpoint = vm.envString("OPTIMISM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 101_774_971);
        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        weth = IWETH9(WETH9_OPTIMISM);
    }

    function testAddLiquidityWethStEth() public {
        address poolAddress = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
        IERC20 lpToken = IERC20(pool.token());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0;

        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, false);

        uint256 afterBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance, preBalance - amounts[0]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWethStEth() public {
        address poolAddress = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
        IERC20 lpToken = IERC20(pool.token());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 0;

        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, false);

        uint256 preBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0;

        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance > preBalance);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityRethWstEth() public {
        address poolAddress = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, false);

        uint256 afterBalance = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance, preBalance - amounts[0]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityRethWstEth() public {
        address poolAddress = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 0 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, false);

        uint256 preBalance = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 0;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance > preBalance);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityEthFrxEth() public {
        address poolAddress = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        IERC20 lpToken = IERC20(0xf43211935C781D5ca1a41d2041F397B8A7366C7A);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        vm.deal(address(this), 2 ether);

        deal(address(FRXETH_MAINNET), address(this), 2 * 1e18);

        uint256 preEthBalance = address(this).balance;
        uint256 preBalance = IERC20(FRXETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 afterEthBalance = address(this).balance;
        uint256 afterBalance = IERC20(FRXETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterEthBalance, preEthBalance - amounts[0]);
        assertEq(afterBalance, preBalance - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityEthFrxEth() public {
        address poolAddress = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        IERC20 lpToken = IERC20(0xf43211935C781D5ca1a41d2041F397B8A7366C7A);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        vm.deal(address(this), 2 ether);

        deal(address(FRXETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 preBalance1 = IERC20(FRXETH_MAINNET).balanceOf(address(this));
        // we track WETH as we auto-wrap on receiving Ether
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance1 = IERC20(FRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityEthSeth() public {
        address poolAddress = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
        IERC20 lpToken = IERC20(0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        vm.deal(address(this), 3 ether);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
        vm.prank(sethWhale);
        IERC20(SETH_MAINNET).approve(address(this), 2 * 1e18);
        vm.prank(sethWhale);
        IERC20(SETH_MAINNET).transfer(address(this), 2 * 1e18);

        uint256 preEthBalance = address(this).balance;
        uint256 preBalance = IERC20(SETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 afterEthBalance = address(this).balance;
        uint256 afterBalance = IERC20(SETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterEthBalance, preEthBalance - amounts[0]);
        assertEq(afterBalance, preBalance - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityEthSeth() public {
        address poolAddress = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
        IERC20 lpToken = IERC20(0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        vm.deal(address(this), 3 ether);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
        vm.prank(sethWhale);
        IERC20(SETH_MAINNET).approve(address(this), 2 * 1e18);
        vm.prank(sethWhale);
        IERC20(SETH_MAINNET).transfer(address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 preBalance1 = IERC20(SETH_MAINNET).balanceOf(address(this));
        // we track WETH as we auto-wrap on receiving Ether
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance1 = IERC20(SETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));

        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityEthSethOptimism() public {
        forkOptimism();

        address poolAddress = 0x7Bc5728BC2b59B45a58d9A576E2Ffc5f0505B35E;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        vm.deal(address(this), 3 ether);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x12478d1a60a910C9CbFFb90648766a2bDD5918f5;
        vm.startPrank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 2 * 1e18);
        IERC20(SETH_OPTIMISM).transfer(address(this), 2 * 1e18);
        vm.stopPrank();

        uint256 preEthBalance = address(this).balance;
        uint256 preBalance = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 afterEthBalance = address(this).balance;
        uint256 afterBalance = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterEthBalance, preEthBalance - amounts[0]);
        assertEq(afterBalance, preBalance - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityEthSethOptimism() public {
        forkOptimism();

        address poolAddress = 0x7Bc5728BC2b59B45a58d9A576E2Ffc5f0505B35E;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        vm.deal(address(this), 3 ether);

        // Using whale for funding since storage slot overwrite is not working for proxy ERC-20s
        address sethWhale = 0x12478d1a60a910C9CbFFb90648766a2bDD5918f5;
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).approve(address(this), 3 * 1e18);
        vm.prank(sethWhale);
        IERC20(SETH_OPTIMISM).transfer(address(this), 3 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 preBalance1 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        // we track WETH as we auto-wrap on receiving Ether
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance1 = IERC20(SETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityEthWstethOptimism() public {
        forkOptimism();

        address poolAddress = 0xB90B9B1F91a01Ea22A182CD84C1E22222e39B415;
        IERC20 lpToken = IERC20(0xEfDE221f306152971D8e9f181bFe998447975810);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(this), 3 ether);
        deal(address(WSTETH_OPTIMISM), address(this), 2 * 1e18);

        uint256 preEthBalance = address(this).balance;
        uint256 preBalance = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 afterEthBalance = address(this).balance;
        uint256 afterBalance = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterEthBalance, preEthBalance - amounts[0]);
        assertEq(afterBalance, preBalance - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityEthWstethOptimism() public {
        forkOptimism();

        address poolAddress = 0xB90B9B1F91a01Ea22A182CD84C1E22222e39B415;
        IERC20 lpToken = IERC20(0xEfDE221f306152971D8e9f181bFe998447975810);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(this), 3 ether);
        deal(address(WSTETH_OPTIMISM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 preBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        // we track WETH as we auto-wrap on receiving Ether
        uint256 preBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance1 = IERC20(WSTETH_OPTIMISM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH9_OPTIMISM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityEthWstethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        IERC20 lpToken = IERC20(0xDbcD16e622c95AcB2650b38eC799f76BFC557a0b);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(this), 3 ether);
        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 preEthBalance = address(this).balance;
        uint256 preBalance = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 afterEthBalance = address(this).balance;
        uint256 afterBalance = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterEthBalance, preEthBalance - amounts[0]);
        assertEq(afterBalance, preBalance - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityEthWstethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        IERC20 lpToken = IERC20(0xDbcD16e622c95AcB2650b38eC799f76BFC557a0b);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(this), 3 ether);
        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, poolAddress, address(lpToken), weth, true);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        // we track WETH as we auto-wrap on receiving Ether
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0.5 * 1e18;
        withdrawAmounts[1] = 0.5 * 1e18;
        CurveV2FactoryCryptoAdapter.removeLiquidity(withdrawAmounts, preLpBalance, poolAddress, address(lpToken), weth);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    // TODO: figure out the testing approach with Adapter being now a library

    /// @dev This is an integration test for the Solver project. More information is available in the README.
    // function testAddLiquidityUsingSolver() public {
    //     address poolAddress = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
    //     ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
    //     IERC20 lpToken = IERC20(pool.token());

    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = 0.5 * 1e18;
    //     amounts[1] = 0;

    //     deal(address(WETH_MAINNET), address(this), 2 * 1e18);

    //     uint256 preBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
    //     uint256 preLpBalance = lpToken.balanceOf(address(this));

    //     (bytes32[] memory commands, bytes[] memory elements) =
    //         ReadPlan.getPayload(vm, "curvev2-add-liquidity.json", address(this));
    //     CurveV2FactoryCryptoAdapter.execute(address(solver), commands, elements);

    //     uint256 afterBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
    //     uint256 afterLpBalance = lpToken.balanceOf(address(this));

    //     assertEq(afterBalance, preBalance - amounts[0]);
    //     assert(afterLpBalance > preLpBalance);
    // }

    /// @dev This is an integration test for the Solver project. More information is available in the README.
    // function testRemoveLiquidityUsingSolver() public {
    //     address poolAddress = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
    //     ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
    //     IERC20 lpToken = IERC20(pool.token());

    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = 1.5 * 1e18;
    //     amounts[1] = 0;

    //     deal(address(WETH_MAINNET), address(this), 2 * 1e18);

    //     uint256 minLpMintAmount = 1;

    //     bytes memory extraParams = abi.encode(poolAddress, address(lpToken), false);
    //     CurveV2FactoryCryptoAdapter.addLiquidity(amounts, minLpMintAmount, extraParams);

    //     uint256 preBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
    //     uint256 preLpBalance = lpToken.balanceOf(address(this));

    //     uint256[] memory withdrawAmounts = new uint256[](2);
    //     withdrawAmounts[0] = 0.5 * 1e18;
    //     withdrawAmounts[1] = 0;

    //     (bytes32[] memory commands, bytes[] memory elements) =
    //         ReadPlan.getPayload(vm, "curvev2-remove-liquidity.json", address(this));
    //     CurveV2FactoryCryptoAdapter.execute(address(solver), commands, elements);

    //     uint256 afterBalance = IERC20(WETH_MAINNET).balanceOf(address(this));
    //     uint256 afterLpBalance = lpToken.balanceOf(address(this));

    //     assert(afterBalance > preBalance);
    //     assert(afterLpBalance < preLpBalance);
    // }
}
