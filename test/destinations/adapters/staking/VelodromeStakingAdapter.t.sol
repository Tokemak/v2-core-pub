// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { IGauge } from "src/interfaces/external/velodrome/IGauge.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IRouter } from "src/interfaces/external/velodrome/IRouter.sol";
import { VelodromeStakingAdapter } from "src/destinations/adapters/staking/VelodromeStakingAdapter.sol";
import {
    WSTETH_OPTIMISM, WETH9_OPTIMISM, RETH_OPTIMISM, SETH_OPTIMISM, FRXETH_OPTIMISM
} from "test/utils/Addresses.sol";

contract VelodromeStakingAdapterTest is Test {
    IVoter private voter;
    IRouter private router;

    function setUp() public {
        string memory endpoint = vm.envString("OPTIMISM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 86_937_163);
        vm.selectFork(forkId);

        router = IRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);
        voter = IVoter(0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e);
    }

    // Revert On Stake Tests
    function testRevertIfVoterAddressZeroOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        VelodromeStakingAdapter.stakeLPs(address(0), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    function testRevertIfAmountsEmptyOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](0);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amounts.length"));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    function testRevertIfTokenIdsEmptyOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](0);

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "tokenIds.length"));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    function testRevertIfDifferentSizedArraysOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ArrayLengthMismatch.selector, stakeAmounts.length, tokenIds.length, "amounts+tokenIds"
            )
        );
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    function testRevertIfMinLpAmountIsZeroOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 0;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "minLpMintAmount"));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    function testRevertIfPoolAddressZeroOnStake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = address(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
    }

    // Revert On Unstake Tests
    function testRevertIfVoterAddressZeroOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
        uint256 afterStakeLpBalance = IGauge(voter.gauges(pool)).balanceOf(address(this));

        // Unstake
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        VelodromeStakingAdapter.unstakeLPs(address(0), stakeAmounts, tokenIds, afterStakeLpBalance, pool);
    }

    function testRevertIfAmountsEmptyOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
        uint256 afterStakeLpBalance = IGauge(voter.gauges(pool)).balanceOf(address(this));

        // Unstake
        stakeAmounts = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amounts.length"));
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);
    }

    function testRevertIfTokenIdsEmptyOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
        uint256 afterStakeLpBalance = IGauge(voter.gauges(pool)).balanceOf(address(this));

        // Unstake
        tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "tokenIds.length"));
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);
    }

    function testRevertIfDifferentSizedArraysOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
        uint256 afterStakeLpBalance = IGauge(voter.gauges(pool)).balanceOf(address(this));

        // Unstake
        tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ArrayLengthMismatch.selector, stakeAmounts.length, tokenIds.length, "amounts+tokenIds"
            )
        );
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);
    }

    function testRevertIfMaxLpBurnAmountIsZeroOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        // Unstake
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxLpBurnAmount"));
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, 0, pool);
    }

    function testRevertIfPoolAddressZeroOnUnstake() public {
        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, true));
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        uint256 minLpMintAmount = 1;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);
        uint256 afterStakeLpBalance = IGauge(voter.gauges(pool)).balanceOf(address(this));

        // Unstake
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, address(0));
    }

    // WETH/sETH
    function testAddLiquidityWethSeth() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WETH9_OPTIMISM, SETH_OPTIMISM, isStablePool));

        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        address pool = 0xFd7FddFc0A729eCF45fB6B12fA3B71A575E1966F;

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IGauge gauge = IGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }

    // wstETH/sETH
    function testWstEthSethStaking() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, SETH_OPTIMISM, isStablePool));

        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        address pool = 0xB343dae0E7fe28c16EC5dCa64cB0C1ac5F4690AC;

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IGauge gauge = IGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }

    // wstETH/WETH
    function testWstEthWethStaking() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(WSTETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        address pool = 0xBf205335De602ac38244F112d712ab04CB59A498;

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IGauge gauge = IGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }

    // frxETH/WETH
    function testFrxEthWethStaking() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(FRXETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        address pool = 0x63642a192BAb08B09A70a997bb35B36b9286B01e;

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IGauge gauge = IGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }

    // WETH/rETH
    function testWethRethStaking() public {
        bool isStablePool = true;

        IERC20 lpToken = IERC20(router.pairFor(RETH_OPTIMISM, WETH9_OPTIMISM, isStablePool));

        deal(address(lpToken), address(this), 10 * 1e18);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        address pool = 0x69F795e2d9249021798645d784229e5bec2a5a25;

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IGauge gauge = IGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = lpToken.balanceOf(address(this));
        VelodromeStakingAdapter.stakeLPs(address(voter), stakeAmounts, tokenIds, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        VelodromeStakingAdapter.unstakeLPs(address(voter), stakeAmounts, tokenIds, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }
}
