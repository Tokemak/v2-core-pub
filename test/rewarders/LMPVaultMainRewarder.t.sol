// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { LMPVaultMainRewarder } from "src/rewarders/LMPVaultMainRewarder.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { Test } from "forge-std/Test.sol";

// solhint-disable func-name-mixedcase

contract LMPVaultMainRewarderTest is Test {
    address public systemRegistry;
    address public stakeTracker;
    address public accessController;
    MockERC20 public rewardToken;
    MockERC20 public stakingToken;
    address public staker; // Address of user being staked on behalf of.

    uint256 public newRewardRatio = 1;
    uint256 public durationInBlock = 100;
    uint256 public stakeAmount = 1000;

    LMPVaultMainRewarder public rewarder;

    function setUp() public virtual {
        systemRegistry = makeAddr("SYSTEM_REGISTRY");
        stakeTracker = address(this); // Allows this contract to stake and withdraw.
        accessController = makeAddr("ACCESS_CONTROLLER");
        rewardToken = new MockERC20();
        stakingToken = new MockERC20();
        staker = makeAddr("STAKER");

        stakingToken.mint(stakeTracker, stakeAmount);

        // Mock access controller call.
        vm.mockCall(systemRegistry, abi.encodeWithSignature("accessController()"), abi.encode(accessController));
        // Mock reward token call.
        vm.mockCall(systemRegistry, abi.encodeWithSignature("isRewardToken(address)"), abi.encode(true));

        rewarder = new LMPVaultMainRewarder(
            ISystemRegistry(systemRegistry),
            stakeTracker,
            address(rewardToken),
            newRewardRatio,
            durationInBlock,
            false,
            address(stakingToken)
        );
    }
}

contract WithdrawLMPRewarder is LMPVaultMainRewarderTest {
    uint256 public withdrawAmount = 450;

    function setUp() public override {
        super.setUp();

        // Mock GPToke and Toke calls.
        vm.mockCall(systemRegistry, abi.encodeWithSignature("gpToke()"), abi.encode(makeAddr("GP_TOKE")));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("toke()"), abi.encode(makeAddr("TOKE")));

        stakingToken.approve(address(rewarder), stakeAmount);
        rewarder.stake(staker, stakeAmount);
    }

    function test_RevertsWhenWithdrawingOverAllowance() public {
        vm.expectRevert();
        rewarder.withdraw(staker, stakeAmount + 1, false);
    }

    function test_ProperBalanceUpdates_AndTransfers() public {
        uint256 userRewarderBalanceBefore = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceBefore = stakingToken.balanceOf(staker);
        uint256 stakeTrackerRewardBalanceBefore = rewarder.balanceOf(stakeTracker);
        uint256 stakeTrackerStakingTokenBalanceBefore = stakingToken.balanceOf(stakeTracker);

        assertEq(userRewarderBalanceBefore, stakeAmount);
        assertEq(userStakingTokenBalanceBefore, 0);
        assertEq(stakeTrackerRewardBalanceBefore, 0);
        assertEq(stakeTrackerStakingTokenBalanceBefore, 0);

        rewarder.withdraw(staker, withdrawAmount, false);

        uint256 userRewarderBalanceAfter = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceAfter = stakingToken.balanceOf(staker);
        uint256 stakeTrackerRewardBalanceAfter = rewarder.balanceOf(stakeTracker);
        uint256 stakeTrackerStakingBalanceAfter = stakingToken.balanceOf(stakeTracker);

        assertEq(userRewarderBalanceAfter, userRewarderBalanceBefore - withdrawAmount);
        assertEq(userStakingTokenBalanceAfter, withdrawAmount);
        assertEq(stakeTrackerRewardBalanceAfter, 0);
        assertEq(stakeTrackerStakingBalanceAfter, 0);
    }

    function test_ProperlyClaimsRewards() public {
        rewardToken.mint(address(this), stakeAmount);
        rewardToken.approve(address(rewarder), stakeAmount);

        // Mock call to access control to bypass `onlyWhitelist` modifier on queueing rewards.
        vm.mockCall(accessController, abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
        rewarder.queueNewRewards(stakeAmount);

        // Only one staker, should claim all rewards over lock duration.
        vm.roll(block.number + durationInBlock);

        rewarder.withdraw(staker, stakeAmount, true);

        assertEq(rewardToken.balanceOf(staker), stakeAmount);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(address(rewarder)), 0);
    }
}

contract StakeLMPRewarder is LMPVaultMainRewarderTest {
    uint256 public localStakeAmount = 450;

    function setUp() public override {
        super.setUp();

        // Max approve for overage tests.
        stakingToken.approve(address(rewarder), type(uint256).max);
    }

    function test_RevertsWhenStakingMoreThanAvailable() external {
        vm.expectRevert();
        rewarder.stake(staker, stakeAmount + 1);
    }

    function test_ProperlyUpdatesBalances_AndTransfers() external {
        uint256 userRewarderBalanceBefore = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalancBefore = stakingToken.balanceOf(staker);
        uint256 stakeTrackerRewarderBalanceBefore = rewardToken.balanceOf(stakeTracker);
        uint256 stakeTrackerStakingTokenBalanceBefore = stakingToken.balanceOf(stakeTracker);

        assertEq(userRewarderBalanceBefore, 0);
        assertEq(userStakingTokenBalancBefore, 0);
        assertEq(stakeTrackerRewarderBalanceBefore, 0);
        assertEq(stakeTrackerStakingTokenBalanceBefore, stakeAmount);

        rewarder.stake(staker, localStakeAmount);

        uint256 userRewardBalanceAfter = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceAfter = stakingToken.balanceOf(staker);
        uint256 stakeTrackerRewarderBalanceAfter = rewardToken.balanceOf(stakeTracker);
        uint256 stakeTrackerStakingTokenBalanceAfter = stakingToken.balanceOf(stakeTracker);

        assertEq(userRewardBalanceAfter, userRewarderBalanceBefore + localStakeAmount);
        assertEq(userStakingTokenBalanceAfter, 0);
        assertEq(stakeTrackerRewarderBalanceAfter, 0);
        assertEq(stakeTrackerStakingTokenBalanceAfter, stakeAmount - localStakeAmount);
    }
}
