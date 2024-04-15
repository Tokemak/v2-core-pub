// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { CurveV2FactoryCryptoAdapter } from "src/destinations/adapters/CurveV2FactoryCryptoAdapter.sol";
import { ICryptoSwapPool } from "src/interfaces/external/curve/ICryptoSwapPool.sol";
import {
    WETH_MAINNET,
    RETH_MAINNET,
    SETH_MAINNET,
    FRXETH_MAINNET,
    WETH9_OPTIMISM,
    SETH_OPTIMISM,
    WSTETH_OPTIMISM,
    WSTETH_ARBITRUM,
    WETH_ARBITRUM
} from "test/utils/Addresses.sol";

contract CurveV2FactoryCryptoAdapterTest is Test {
    uint256 public mainnetFork;

    IWETH9 private weth;

    ///@notice Auto-wrap on receive as system operates with WETH
    receive() external payable {
        // weth.deposit{ value: msg.value }();
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_000_000);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

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

    function testRemoveLiquidityEthStEth() public {
        address poolAddress = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        IERC20 lpToken = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 0;

        vm.deal(address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

    function testRemoveLiquidityWethCbEth() public {
        address poolAddress = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
        IERC20 lpToken = IERC20(pool.token());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 0;

        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        _addLiquidity(amounts, minLpMintAmount, poolAddress, false);

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

    function testRemoveLiquidityRethWstEth() public {
        address poolAddress = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 0 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        _addLiquidity(amounts, minLpMintAmount, poolAddress, false);

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

    function testRemoveLiquidityEthFrxEth() public {
        address poolAddress = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        IERC20 lpToken = IERC20(0xf43211935C781D5ca1a41d2041F397B8A7366C7A);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        vm.deal(address(this), 2 ether);

        deal(address(FRXETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

        _addLiquidity(amounts, minLpMintAmount, poolAddress, true);

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

    /**
     * @notice Deploy liquidity to Curve pool
     *  @dev Calls to external contract
     *  @dev We trust sender to send a true Curve poolAddress.
     *       If it's not the case it will fail in the remove_liquidity_one_coin part
     *  @param amounts Amounts of coin to deploy
     *  @param minLpMintAmount Amount of LP tokens to mint on deposit
     *  @param poolAddress Curve pool address
     *  @param useEth A flag to whether use ETH or WETH for deployment
     */
    function _addLiquidity(
        uint256[] memory amounts,
        uint256 minLpMintAmount,
        address poolAddress,
        bool useEth
    ) private {
        uint256 nTokens = amounts.length;
        address[] memory tokens = new address[](nTokens);
        uint256[] memory coinsBalancesBefore = new uint256[](nTokens);
        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 amount = amounts[i];
            address coin = ICryptoSwapPool(poolAddress).coins(i);
            tokens[i] = coin;
            if (amount > 0 && coin != LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                LibAdapter._approve(IERC20(coin), poolAddress, amount);
            }
            coinsBalancesBefore[i] = coin == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER
                ? address(this).balance
                : IERC20(coin).balanceOf(address(this));
        }

        _runDeposit(amounts, minLpMintAmount, poolAddress, useEth);
    }

    function _runDeposit(
        uint256[] memory amounts,
        uint256 minLpMintAmount,
        address poolAddress,
        bool useEth
    ) private returns (uint256 deployed) {
        uint256 nTokens = amounts.length;
        ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
        if (useEth) {
            // slither-disable-start arbitrary-send-eth
            if (nTokens == 2) {
                uint256[2] memory staticParamArray = [amounts[0], amounts[1]];
                deployed = pool.add_liquidity{ value: amounts[0] }(staticParamArray, minLpMintAmount);
            } else if (nTokens == 3) {
                uint256[3] memory staticParamArray = [amounts[0], amounts[1], amounts[2]];
                deployed = pool.add_liquidity{ value: amounts[0] }(staticParamArray, minLpMintAmount);
            } else if (nTokens == 4) {
                uint256[4] memory staticParamArray = [amounts[0], amounts[1], amounts[2], amounts[3]];
                deployed = pool.add_liquidity{ value: amounts[0] }(staticParamArray, minLpMintAmount);
            }
            // slither-disable-end arbitrary-send-eth
        } else {
            if (nTokens == 2) {
                uint256[2] memory staticParamArray = [amounts[0], amounts[1]];
                deployed = pool.add_liquidity(staticParamArray, minLpMintAmount);
            } else if (nTokens == 3) {
                uint256[3] memory staticParamArray = [amounts[0], amounts[1], amounts[2]];
                deployed = pool.add_liquidity(staticParamArray, minLpMintAmount);
            } else if (nTokens == 4) {
                uint256[4] memory staticParamArray = [amounts[0], amounts[1], amounts[2], amounts[3]];
                deployed = pool.add_liquidity(staticParamArray, minLpMintAmount);
            }
        }
        if (deployed < minLpMintAmount) {
            revert LibAdapter.MinLpAmountNotReached();
        }
    }
}
