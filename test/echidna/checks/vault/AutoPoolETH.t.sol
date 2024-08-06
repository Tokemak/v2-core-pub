// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase, no-console

import { Test } from "forge-std/Test.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolETHUsage } from "test/echidna/fuzz/vault/AutopoolETHTests.sol";
import { AutopoolETHTest } from "test/echidna/fuzz/vault/AutopoolETHTests.sol";
import { CryticERC4626Harness } from "test/echidna/fuzz/vault/CryticProperties.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AutopoolETHTests is Test, AutopoolETHUsage {
    constructor() AutopoolETHUsage() { }

    function test_Construction() public {
        assertTrue(address(_pool) != address(0), "pool");
    }

    function test_Deployment() public {
        new AutopoolETHTest();
    }

    function test_DeploymentCrytic() public {
        new CryticERC4626Harness();
    }

    function test_Deposit() public {
        address user = makeAddr("user1");
        uint256 amount = 2e18;
        _vaultAsset.mint(address(this), amount);
        _vaultAsset.approve(address(_pool), amount);
        _pool.deposit(amount, user);
    }

    function test_NavDecreaseCheckMutationWorks() public {
        address user = makeAddr("user1");
        uint256 amount = 2e18;
        _vaultAsset.mint(address(this), amount);
        _vaultAsset.approve(address(_pool), amount);
        _pool.deposit(amount, user);

        _vaultAsset.mint(address(this), 1e18);
        _vaultAsset.approve(address(_pool), 1e18);

        _pool.setNextDepositGetsDoubleShares(true);

        uint256 assetsBefore = _pool.convertToAssets(1e18);

        _pool.setDisableNavDecreaseCheck(false);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETH.NavDecreased.selector, 10_000, 7500));
        _pool.deposit(1e18, user);

        _pool.setDisableNavDecreaseCheck(true);
        _pool.deposit(1e18, user);

        uint256 assetsAfter = _pool.convertToAssets(1e18);
        assertTrue(assetsAfter < assetsBefore, "navPerShareLess");
    }

    function test_UserDepositFns() public {
        // User 1
        userDeposit(0, 100e18, true);
        userDeposit(0, 100e18, false);

        // User 2
        userDeposit(100, 10e18, true);
        userDeposit(100, 10e18, false);

        // User 3
        userDeposit(255, 9e18, true);
        userDeposit(255, 9e18, false);

        assertEq(_pool.balanceOf(_user1), 200e18);
        assertEq(_pool.balanceOf(_user2), 20e18);
        assertEq(_pool.balanceOf(_user3), 18e18);
    }

    function test_UserMintFns() public {
        userMint(0, 100e18, true);
        userMint(0, 100e18, false);

        userMint(100, 10e18, true);
        userMint(100, 10e18, false);

        userMint(255, 9e18, true);
        userMint(255, 9e18, false);

        assertEq(_pool.balanceOf(_user1), 200e18);
        assertEq(_pool.balanceOf(_user2), 20e18);
        assertEq(_pool.balanceOf(_user3), 18e18);
    }

    function test_UserRedeemFns() public {
        userMint(0, 100e18, true);
        userMint(0, 100e18, false);

        userMint(100, 10e18, true);
        userMint(100, 10e18, false);

        userMint(255, 9e18, true);
        userMint(255, 9e18, false);

        assertEq(_vaultAsset.balanceOf(_user1), 0);
        assertEq(_vaultAsset.balanceOf(_user2), 0);
        assertEq(_vaultAsset.balanceOf(_user3), 0);

        userRedeem(0, 50e18);
        userRedeemAllowance(0, 40e18, address(8));

        userRedeem(100, 5e18);
        userRedeemAllowance(100, 4e18, address(9));

        userRedeem(255, 1e18);
        userRedeemAllowance(255, 2e18, address(10));

        assertEq(_vaultAsset.balanceOf(_user1), 90e18);
        assertEq(_vaultAsset.balanceOf(_user2), 9e18);
        assertEq(_vaultAsset.balanceOf(_user3), 3e18);

        assertEq(_pool.balanceOf(_user1), 110e18);
        assertEq(_pool.balanceOf(_user2), 11e18);
        assertEq(_pool.balanceOf(_user3), 15e18);
    }

    function test_UserWithdrawFns() public {
        userMint(0, 100e18, true);
        userMint(0, 100e18, false);

        userMint(100, 10e18, true);
        userMint(100, 10e18, false);

        userMint(255, 9e18, true);
        userMint(255, 9e18, false);

        assertEq(_vaultAsset.balanceOf(_user1), 0);
        assertEq(_vaultAsset.balanceOf(_user2), 0);
        assertEq(_vaultAsset.balanceOf(_user3), 0);

        userWithdraw(0, 50e18);
        userWithdrawAllowance(0, 40e18, address(8));

        userWithdraw(100, 5e18);
        userWithdrawAllowance(100, 4e18, address(9));

        userWithdraw(255, 1e18);
        userWithdrawAllowance(255, 2e18, address(10));

        assertEq(_vaultAsset.balanceOf(_user1), 90e18);
        assertEq(_vaultAsset.balanceOf(_user2), 9e18);
        assertEq(_vaultAsset.balanceOf(_user3), 3e18);

        assertEq(_pool.balanceOf(_user1), 110e18);
        assertEq(_pool.balanceOf(_user2), 11e18);
        assertEq(_pool.balanceOf(_user3), 15e18);
    }

    function test_DonateFns() public {
        userDonate(0, 100e18);
        userDonate(100, 100e18);
        userDonate(255, 100e18);
        randomDonate(100e18, address(777_777));

        assertEq(_pool.totalSupply(), 100_000); // Autopool init deposit.
        assertEq(_vaultAsset.balanceOf(address(_pool)), 400_000_000_000_000_100_000);
    }

    function test_Rebalance() public {
        userMint(0, 100e18, true);

        // 250 should give us a destination bucket of 3, which is idle, 0,1,2 are the destinations
        // 1 will give us bucket 0, destination 1
        // So this is a rebalance from idle to destination 1, for 50% (128 == 255/2) of the deposited idle, tokens with
        // 0 price tweak
        // The tokens are initially all priced 1:1 in the test so we should end up with up
        // with 50 left in idle and 50 destination vault 1 tokens
        rebalance(250, 1, uint8(128), 0);

        assertEq(_vaultAsset.balanceOf(address(_pool)), 50_000_000_000_000_050_000, "basePoolBal");
        assertEq(_destVault1.balanceOf(address(_pool)), 50_000_000_000_000_050_000, "poolDv1Bal");
        assertEq(
            IERC20(_destVault1Underlyer).balanceOf(address(_destVault1)), 50_000_000_000_000_050_000, "tokenBalInDv1"
        );

        // 1 will give us bucket 0, destination 1
        // 75 will give us bucket 1, destination 2
        // 255 will take 100% of D1 into D2
        // Prices are still 1:1 so it should be
        rebalance(1, 75, uint8(255), 0);

        // Should see no change to idle
        assertEq(_vaultAsset.balanceOf(address(_pool)), 50_000_000_000_000_050_000, "basePoolBal");

        // D1 should be gone
        assertEq(_destVault1.balanceOf(address(_pool)), 0e18, "poolDv1Bal");
        assertEq(IERC20(_destVault1Underlyer).balanceOf(address(_destVault1)), 0e18, "tokenBalInDv1");

        // D2
        assertEq(_destVault2.balanceOf(address(_pool)), 50_000_000_000_000_050_000, "poolDv2Bal");
        assertEq(
            IERC20(_destVault2Underlyer).balanceOf(address(_destVault2)), 50_000_000_000_000_050_000, "tokenBalInDv2"
        );

        // 75 will give us bucket 1, destination 2
        // 160 will give us bucket 2, destination 3
        // 128 will take 50% of D2 tokens into D3
        // Price tweak should give us about a ~3% reduction of "in" tokens (slippage)
        rebalance(75, 160, uint8(128), int16(-1000));

        // Should see no change to idle
        assertEq(_vaultAsset.balanceOf(address(_pool)), 50_000_000_000_000_050_000, "basePoolBal");

        // D2 should be at half
        assertEq(_destVault2.balanceOf(address(_pool)), 25_000_000_000_000_025_000, "poolDv1Bal");
        assertEq(
            IERC20(_destVault2Underlyer).balanceOf(address(_destVault2)), 25_000_000_000_000_025_000, "tokenBalInDv1"
        );

        // D3
        assertEq(_destVault3.balanceOf(address(_pool)), 24_237_060_546_875_024_238, "poolDv3Bal");
        assertEq(
            IERC20(_destVault3Underlyer).balanceOf(address(_destVault3)), 24_237_060_546_875_024_238, "tokenBalInDv3"
        );
    }

    function test_RecognizeLossEntire() public {
        _runLossScenario(0);
    }

    function test_RecognizeLossSubOne() public {
        _runLossScenario(1);
    }

    function test_RecognizeLossSubTwo() public {
        _runLossScenario(2);
    }

    function test_RecognizeLossSubThree() public {
        _runLossScenario(3);
    }

    function test_DebtReport() public {
        userMint(0, 100e18, true);

        rebalance(250, 1, uint8(128), 0);

        debtReport(3);
    }

    function test_DebtReportWithPriceChange() public {
        userMint(0, 100e18, true);

        // 100e18 + 100_000 wei init deposit idle -> 1/2 going to dv1
        rebalance(250, 1, uint8(128), 0);

        assertEq(_pool.getAssetBreakdown().totalIdle, 50_000_000_000_000_050_000, "round1Idle");
        assertEq(_pool.getAssetBreakdown().totalDebt, 50_000_000_000_000_050_000, "round1Debt");
        assertEq(_pool.getAssetBreakdown().totalDebtMin, 50_000_000_000_000_050_000, "round1DebtMin");
        assertEq(_pool.getAssetBreakdown().totalDebtMax, 50_000_000_000_000_050_000, "round1DebtMax");

        // Increase the dv1 price by ~6.3%
        tweakDestVaultUnderlyerPrice(1, 8);

        debtReport(3);

        assertEq(_pool.getAssetBreakdown().totalIdle, 50_000_000_000_000_050_000, "round2Idle");
        assertEq(_pool.getAssetBreakdown().totalDebt, 53_149_606_299_212_651_549, "round2Debt");
        assertEq(_pool.getAssetBreakdown().totalDebtMin, 53_149_606_299_212_651_549, "round2DebtMin");
        assertEq(_pool.getAssetBreakdown().totalDebtMax, 53_149_606_299_212_651_549, "round2DebtMax");

        // Skew the safe price up 3.93
        setDestVaultUnderlyerSafeTweak(1, 5);
        // Skew the spot price down 7.81%
        setDestVaultUnderlyerSpotTweak(1, -10);

        debtReport(3);

        assertEq(_pool.getAssetBreakdown().totalIdle, 50_000_000_000_000_050_000, "round2Idle");
        assertEq(_pool.getAssetBreakdown().totalDebt, 52_119_701_895_653_843_394, "round2Debt");
        assertEq(_pool.getAssetBreakdown().totalDebtMin, 48_997_293_307_086_663_147, "round2DebtMin");
        assertEq(_pool.getAssetBreakdown().totalDebtMax, 55_242_110_484_221_023_642, "round2DebtMax");
    }

    function test_QueueDestinationRewards() public {
        queueDestinationRewards(0, 100e18);

        assertEq(_vaultAsset.balanceOf(address(_destVault1.rewarder())), 100e18);
    }

    function test_SetStreamingFeeSink() public {
        setStreamingFeeSink(address(9));

        assertEq(_pool.getFeeSettings().feeSink, address(9));
    }

    function test_SetPeriodicFeeSink() public {
        setPeriodicFeeSink((address(8)));

        assertEq(_pool.getFeeSettings().periodicFeeSink, address(8));
    }

    function test_SetStreamingFee1() public {
        vm.warp(1 days);

        setStreamingFee(900);

        assertEq(_pool.getFeeSettings().streamingFeeBps, 900);
    }

    function setPeriodicFee() public {
        setPeriodicFee((800));

        assertEq(_pool.getFeeSettings().periodicFeeBps, 800);
    }

    function _runLossScenario(uint256 lossSub) private {
        userMint(0, 100e18, true);

        rebalance(250, 1, uint8(128), 0);
        rebalance(1, 75, uint8(255), 0);
        rebalance(75, 160, uint8(128), int16(-1000));

        uint256 loss = _pool.totalAssets();
        _pool.recognizeLoss(loss - lossSub);
    }
}

contract Scenarios is Test, AutopoolETHUsage {
    constructor() AutopoolETHUsage() { }

    function test_NavPerShareDecrease_Scenario1() public {
        // User 1 deposit, asUser == false so a deposit on behalf of
        // Balance 512955032.591145248510199728
        userDeposit(0, 512_955_032_591_145_248_510_199_728, false);

        // Tweak the safe price of destination .07%
        // 1e18 to 1.007874015748031496e18
        setDestVaultUnderlyerSafeTweak(0, 1);

        // 193 gives us index==3, so idle out
        // 1 gives us index==0, so destination 1
        // 6 is giving us a percent out of ~2.35% of the balance; 10259100.651822904970203994
        // 115 is giving us positive slippage on the rebalance
        //    - that'll be 115/32767 or 0.350962859% positive slippage
        //    - 10295106.284775559594416569 coming back in of dv1 shares
        rebalance(193, 1, 6, 115);

        rebalance(201, 64, 13, 137);

        userWithdraw(0, 489_474_113_706_290_215_264_018_292);

        assertEq(_navPerShareLastNonOpStart, _navPerShareLastNonOpEnd);
    }
}
