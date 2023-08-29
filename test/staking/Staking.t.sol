// solhint-disable no-console, not-rely-on-time, func-name-mixedcase
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IGPToke, GPToke, BaseTest } from "test/BaseTest.t.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";

contract StakingTest is BaseTest {
    uint256 private stakeAmount = 1 ether;
    uint256 private maxDuration = 1461 days;

    event Stake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Unstake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Extend(
        address indexed user,
        uint256 lockupId,
        uint256 amount,
        uint256 oldEnd,
        uint256 newEnd,
        uint256 oldPoints,
        uint256 newPoints
    );
    event RewardsAdded(uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    // solhint-disable-next-line var-name-mixedcase
    uint256 public TOLERANCE = 1e14; // 0.01% (1e18 being 100%)

    // Fuzzing constraints
    uint256 public constant MAX_STAKE_AMOUNT = 100e6 * 1e18; // default 100m toke
    uint256 public constant MAX_REWARD_ADD = 1e9 * 1e18; // default 1B eth

    function setUp() public virtual override {
        super.setUp();

        // get some initial toke
        deal(address(toke), address(this), 10 ether);

        deployGpToke();

        assertEq(gpToke.name(), "Staked Toke");
        assertEq(gpToke.symbol(), "accToke");

        // approve future spending
        toke.approve(address(gpToke), toke.balanceOf(address(this)));
    }

    function testStakingCanBePaused() public {
        // make sure not paused
        assertEq(gpToke.paused(), false);
        // stake
        gpToke.stake(stakeAmount, ONE_YEAR);
        // pause
        gpToke.pause();
        // try to stake again (should revert)
        vm.expectRevert("Pausable: paused");
        gpToke.stake(stakeAmount, ONE_YEAR);
        // unpause
        gpToke.unpause();
        // stake again
        gpToke.stake(stakeAmount, ONE_YEAR);
    }

    function testTransfersDisabled() public {
        vm.expectRevert(IGPToke.TransfersDisabled.selector);
        gpToke.transfer(address(0), 1);
        vm.expectRevert(IGPToke.TransfersDisabled.selector);
        gpToke.transferFrom(address(this), address(0), 1);
    }

    function testPreviewPoints() public {
        (uint256 points, uint256 end) = gpToke.previewPoints(stakeAmount, ONE_YEAR);
        assertEq(points, 1_799_999_999_999_999_984);
        assertEq(end, block.timestamp + ONE_YEAR);
    }

    function testInvalidDurationsNotAllowed() public {
        // try to stake too short
        vm.expectRevert(IGPToke.StakingDurationTooShort.selector);
        gpToke.stake(stakeAmount, MIN_STAKING_DURATION - 1);
        // try to stake too long
        vm.expectRevert(IGPToke.StakingDurationTooLong.selector);
        gpToke.stake(stakeAmount, maxDuration + 1);
    }

    function testSetMaxDuration() public {
        // regular stake for two years
        gpToke.stake(stakeAmount, 2 * ONE_YEAR);
        // change staking duration to shorter, try staking again (should fail)
        gpToke.setMaxStakeDuration(ONE_YEAR);
        vm.expectRevert();
        gpToke.stake(stakeAmount, 2 * ONE_YEAR);
    }

    function testStakingAndUnstaking(uint256 amount) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);

        //
        // stake
        //
        stake(amount, ONE_YEAR);

        IGPToke.Lockup[] memory lockups = gpToke.getLockups(address(this));
        assert(lockups.length == 1);

        uint256 lockupId = 0;
        IGPToke.Lockup memory lockup = lockups[lockupId];

        assertEq(lockup.amount, amount, "Lockup amount incorrect");
        assertEq(lockup.end, block.timestamp + ONE_YEAR);

        // voting power
        // NOTE: doing exception for comparisons since with low numbers relative tolerance is trickier
        assertApproxEqRel(gpToke.balanceOf(address(this)), (amount * 18) / 10, TOLERANCE, "Voting power incorrect");

        //
        // Unstake
        //

        // make sure can't unstake too early
        vm.warp(block.timestamp + ONE_YEAR - 1);
        vm.expectRevert(IGPToke.NotUnlockableYet.selector);
        gpToke.unstake(lockupId);
        // get to proper timestamp and unlock
        vm.warp(block.timestamp + 1);
        gpToke.unstake(lockupId);
        assertEq(gpToke.balanceOf(address(this)), 0);
    }

    function testStakingMultipleTimePeriods(uint256 amount) public {
        _checkFuzz(amount);
        prepareFunds(address(this), amount * 2);

        // stake 1: 2 years lockup
        stake(amount, 2 * ONE_YEAR);
        // stake 2: 1 year lockup
        warpAndStake(amount, ONE_YEAR, ONE_YEAR);
        // voting power should be identical
        IGPToke.Lockup[] memory lockups = gpToke.getLockups(address(this));
        assert(lockups.length == 2);
        assertEq(lockups[0].points, lockups[1].points, "Lockup points should be identical");

        // unstake first lock (try without warp first)
        vm.expectRevert(IGPToke.NotUnlockableYet.selector);
        gpToke.unstake(0);

        warpAndUnstake(ONE_YEAR, 0);

        IGPToke.Lockup memory lockup0 = gpToke.getLockups(address(this))[0];
        assertEq(lockup0.amount, 0);
        assertEq(lockup0.points, 0);

        // unstake second lock
        gpToke.unstake(1);
        IGPToke.Lockup memory lockup1 = gpToke.getLockups(address(this))[1];
        assertEq(lockup1.amount, 0);
        assertEq(lockup1.points, 0);
        assertEq(gpToke.balanceOf(address(this)), 0);
    }

    function testReceive() public {
        // ensure gpToke.totalSupply() > 0 (otherwise just reverts)
        stake(stakeAmount, ONE_YEAR);

        uint256 balanceBefore = address(this).balance;
        uint256 gpTokeBefore = weth.balanceOf(address(gpToke));

        // send eth to gpToke
        (bool success,) = payable(gpToke).call{ value: stakeAmount }("");
        assertTrue(success);

        assertEq(address(this).balance, balanceBefore - stakeAmount);
        assertEq(weth.balanceOf(address(gpToke)), gpTokeBefore + stakeAmount);
    }

    function testExtend(uint256 amount) public {
        _checkFuzz(amount);
        prepareFunds(address(this), amount);

        // original stake
        stake(amount, ONE_YEAR);
        (uint256 amountBefore,, uint256 pointsBefore) = gpToke.lockups(address(this), 0);
        // extend to 2 years
        vm.expectEmit(true, false, false, false);
        emit Extend(address(this), 0, amountBefore, 0, 0, 0, 0);
        gpToke.extend(0, 2 * ONE_YEAR);
        // verify that duration (and points) increased
        IGPToke.Lockup memory lockup = gpToke.getLockups(address(this))[0];
        assertEq(lockup.amount, amountBefore);
        assertEq(lockup.end, block.timestamp + 2 * ONE_YEAR);
        assert(lockup.points > pointsBefore);
    }

    /* **************************************************************************** */
    /* 						Staking helper methods									*/

    function stake(uint256 amount, uint256 stakeTimespan) private {
        stake(amount, stakeTimespan, address(this));
    }

    function stake(uint256 amount, uint256 stakeTimespan, address user) private {
        vm.assume(amount > 0 && amount < MAX_STAKE_AMOUNT);

        (uint256 points, uint256 end) = gpToke.previewPoints(amount, stakeTimespan);
        vm.expectEmit(true, false, false, false);
        emit Stake(user, 0, amount, end, points);
        gpToke.stake(amount, stakeTimespan);
    }

    function warpAndStake(uint256 amount, uint256 warpTimespan, uint256 stakeTimespan) private {
        vm.warp(block.timestamp + warpTimespan);
        vm.expectEmit(true, false, false, false);
        emit Stake(address(this), 0, 0, 0, 0);
        gpToke.stake(amount, stakeTimespan);
    }

    function warpAndUnstake(uint256 warpTimespan, uint256 lockupId) private {
        vm.expectEmit(true, false, false, false);
        emit Unstake(address(this), 0, 0, 0, 0);
        vm.warp(block.timestamp + warpTimespan);
        gpToke.unstake(lockupId);
    }

    /* **************************************************************************** */
    /* 									Rewards										*/
    /* **************************************************************************** */

    function test_StakingRewards_SingleUser_OneStake(uint256 amount) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);
        address user1 = address(this);

        // stake toke for a year
        stake(amount, ONE_YEAR);
        assertEq(gpToke.totalRewardsEarned(), 0, "No rewards yet");
        assertEq(gpToke.totalRewardsClaimed(), 0);
        assertEq(gpToke.previewRewards(), 0);
        // add new rewards
        topOffRewards(amount);
        // make sure we can claim now
        assertApproxEqRel(gpToke.totalRewardsEarned(), amount, TOLERANCE);
        assertEq(gpToke.totalRewardsClaimed(), 0);
        assertApproxEqRel(gpToke.previewRewards(), amount, TOLERANCE, "Full reward not showing up as available");
        // claim rewards
        collectRewards(user1);
        // make sure: a) no more left to claim, b) claim was logged properly
        assertApproxEqRel(gpToke.totalRewardsEarned(), amount, TOLERANCE);
        assertApproxEqRel(gpToke.totalRewardsClaimed(), amount, TOLERANCE);
        assertEq(gpToke.previewRewards(), 0, "Should have no more rewards to claim");
        assertApproxEqRel(gpToke.rewardsClaimed(address(this)), amount, TOLERANCE);
    }

    function test_StakingRewards_SingleUser_MultipleStakes(uint256 amount) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount * 2); // "*2" in order to account for reward topping up

        address user1 = address(this);
        // stake toke for 2 years
        stake(amount, ONE_YEAR);
        // make sure we can't cash anything yet
        assertEq(gpToke.previewRewards(), 0, "Shouldn't have any rewards yet to claim");

        // add new rewards
        topOffRewards(amount);
        // make sure we can claim now
        assertApproxEqRel(gpToke.previewRewards(), amount, TOLERANCE, "Incorrect new rewards amount");

        // forward a year
        skip(ONE_YEAR);

        stake(amount, ONE_YEAR);
        topOffRewards(amount);
        // verify that only old rewards can be accessed
        assertApproxEqRel(gpToke.previewRewards(), 2 * amount, TOLERANCE, "Incorrect second rewards amount");

        // claim rewards
        collectRewards(user1);
        // make sure: a) no more left to claim, b) claim was logged properly
        assertEq(gpToke.previewRewards(), 0, "should have no more rewards left to claim");
        assertApproxEqRel(
            gpToke.rewardsClaimed(address(this)), 2 * amount, TOLERANCE, "claim rewards amount does not match"
        );
    }

    function test_StakingRewards_MultiUser(uint256 amount) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount * 3); // "*3" in order to account for reward topping up

        //
        // Stakes for user 1

        // add awards (just to have original pot)
        address user1 = address(this);
        vm.label(user1, "user1");

        // stake toke for 2 years
        stake(amount, 2 * ONE_YEAR, user1);
        // make sure we can't cash anything yet
        assertEq(gpToke.previewRewards(), 0, "Shouldn't have any rewards yet to claim");

        // ////////////////////
        // add new rewards
        topOffRewards(amount);

        // make sure we can claim now
        assertApproxEqRel(gpToke.previewRewards(user1), amount, TOLERANCE, "Incorrect new rewards amount");

        // forward a year
        skip(ONE_YEAR);

        //
        // stake as user 2
        //
        address user2 = createAndPrankUser("user2", amount);
        prepareFunds(user2, amount);
        stake(amount, ONE_YEAR, user2);

        // make sure user2 has no rewards yet (even though user1 does)
        assertApproxEqRel(gpToke.previewRewards(user1), amount, TOLERANCE);
        assertApproxEqRel(gpToke.previewRewards(user2), 0, TOLERANCE);

        vm.startPrank(user1);
        topOffRewards(amount);

        // verify rewards
        assertApproxEqRel(gpToke.previewRewards(user1), amount * 3 / 2, TOLERANCE);
        assertApproxEqRel(gpToke.previewRewards(user2), amount / 2, TOLERANCE);

        // claim rewards
        collectRewards(user1);
        collectRewards(user2);

        assertApproxEqRel(gpToke.previewRewards(user1), 0, TOLERANCE);
        assertApproxEqRel(gpToke.rewardsClaimed(user1), amount * 3 / 2, TOLERANCE);
        assertApproxEqRel(gpToke.previewRewards(user2), 0, TOLERANCE);
        assertApproxEqRel(gpToke.rewardsClaimed(user2), amount / 2, TOLERANCE);
    }

    /* **************************************************************************** */
    /* 						Rewards helper methods									*/

    // @dev Top off rewards to make sure there is enough to claim
    function topOffRewards(uint256 _amount) private {
        vm.assume(_amount < MAX_REWARD_ADD);

        // get some weth if not enough to top off rewards
        if (weth.balanceOf(address(this)) < _amount) {
            deal(address(weth), address(this), _amount);
        }

        uint256 wethStakingBalanceBefore = weth.balanceOf(address(gpToke));

        weth.approve(address(gpToke), _amount);

        vm.expectEmit(true, false, false, false);
        emit RewardsAdded(_amount);
        gpToke.addWETHRewards(_amount);

        assertEq(weth.balanceOf(address(gpToke)), wethStakingBalanceBefore + _amount);
    }

    function collectRewards(address user) private {
        vm.startPrank(user);

        uint256 claimTargetAmount = gpToke.previewRewards();

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(user, claimTargetAmount);
        gpToke.collectRewards();

        vm.stopPrank();
    }

    function prepareFunds(address user, uint256 amount) private {
        vm.startPrank(user);

        deal(address(toke), user, amount);
        toke.approve(address(gpToke), amount);
        deal(address(weth), user, amount);
        weth.approve(address(gpToke), amount);
    }

    function _checkFuzz(uint256 amount) private {
        vm.assume(amount >= 10_000 && amount <= MAX_STAKE_AMOUNT);

        // adjust tolerance for small amounts to account for rounding errors
        if (amount < 100_000) {
            TOLERANCE = 1e16;
        }
    }
}
