// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/StdStorage.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// solhint-disable max-line-length
import { BalancerBeethovenAdapter } from "src/destinations/adapters/BalancerBeethovenAdapter.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { TestableVM } from "src/solver/test/TestableVM.sol";
import { SolverCaller } from "src/solver/test/SolverCaller.sol";
import { Errors } from "src/utils/Errors.sol";
import { ReadPlan } from "test/utils/ReadPlan.sol";
import {
    PRANK_ADDRESS,
    RANDOM,
    WETH_MAINNET,
    RETH_MAINNET,
    WSTETH_MAINNET,
    SFRXETH_MAINNET,
    CBETH_MAINNET,
    WSTETH_ARBITRUM,
    WETH_ARBITRUM
} from "test/utils/Addresses.sol";

contract BalancerAdapterTest is Test {
    uint256 public mainnetFork;
    TestableVM public solver;

    IVault private vault;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_536_359);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        solver = new TestableVM();
    }

    function forkArbitrum() private {
        string memory endpoint = vm.envString("ARBITRUM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint);
        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    function testAddLiquidityRevertOnZeroVault() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vault"));
        BalancerBeethovenAdapter.addLiquidity(IVault(address(0)), poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityRevertOnZeroPool() public {
        address poolAddress = address(0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityRevertOnZeroAmounts() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.NoNonZeroAmountProvided.selector));
        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityRevertOnTokenOrderMismatch() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = CBETH_MAINNET;
        tokens[1] = WSTETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.TokenPoolAssetMismatch.selector));
        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityRevertOnWrongTokenInput() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = RETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.TokenPoolAssetMismatch.selector));
        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityRevertOnZeroLpMintAmount() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 0;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "minLpMintAmount"));
        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);
    }

    function testAddLiquidityWstEthCbEth() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthCbEth() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthCbEth() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);

        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 0.5 * 1e18;
        amounts[2] = 0.5 * 1e18;
        amounts[3] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[1]);
        assertEq(afterBalance2, preBalance2 - amounts[2]);
        assertEq(afterBalance3, preBalance3 - amounts[3]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 1.5 * 1e18;
        amounts[2] = 1.5 * 1e18;
        amounts[3] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory minWithdrawAmounts = new uint256[](4);
        minWithdrawAmounts[0] = 0;
        minWithdrawAmounts[1] = 1 * 1e18;
        minWithdrawAmounts[2] = 1 * 1e18;
        minWithdrawAmounts[3] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidity(vault, address(pool), tokens, minWithdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterBalance3 > preBalance3);
        assert(afterLpBalance < preLpBalance);
    }

    function testRemoveLiquidityImbalanceWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 1.5 * 1e18;
        amounts[2] = 1.5 * 1e18;
        amounts[3] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        BalancerBeethovenAdapter.addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](4);
        withdrawAmounts[0] = 0;
        withdrawAmounts[1] = 1 * 1e18;
        withdrawAmounts[2] = 1 * 1e18;
        withdrawAmounts[3] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, address(pool), tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterBalance3 > preBalance3);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);

        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);
        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);
        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        BalancerBeethovenAdapter.addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }
}
