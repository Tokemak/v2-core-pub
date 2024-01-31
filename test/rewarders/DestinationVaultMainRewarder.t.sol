// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { DestinationVaultMainRewarder } from "src/rewarders/DestinationVaultMainRewarder.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Errors } from "src/utils/Errors.sol";

import { Test } from "forge-std/Test.sol";

// TODO: File should be changed to have stake tracker acting on behalf of itself. This is because
// stake tracker is DV in prod.
contract DestinationVaultRewarderTest is Test {
    address public stakeTracker;
    address public systemRegistry;
    address public accessController;
    MockERC20 public rewardToken;
    DestinationVaultMainRewarder public rewarder;

    uint256 public newRewardRatio = 1;
    uint256 public durationInBlock = 100;
    uint256 public stakeAmount = 1000;

    function setUp() public virtual {
        stakeTracker = makeAddr("STAKE_TRACKER");
        systemRegistry = makeAddr("SYSTEM_REGISTRY");
        accessController = makeAddr("ACCESS_CONTROLLER");

        rewardToken = new MockERC20();

        // Mocks
        vm.mockCall(systemRegistry, abi.encodeWithSignature("accessController()"), abi.encode(accessController));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("isRewardToken(address)"), abi.encode(true));

        rewarder = new DestinationVaultMainRewarder(
            ISystemRegistry(systemRegistry), stakeTracker, address(rewardToken), newRewardRatio, durationInBlock, false
        );
    }
}

contract DVRewarderConstructorTest is DestinationVaultRewarderTest {
    function test_RevertsZeroAddressStakeTracker() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_stakeTracker"));
        new DestinationVaultMainRewarder(
            ISystemRegistry(systemRegistry), address(0), address(rewardToken), newRewardRatio, durationInBlock, false
        );
    }

    function test_StakeTrackerSet() public {
        assertEq(rewarder.stakeTracker(), stakeTracker);
    }
}

contract DVRewarderStakeTest is DestinationVaultRewarderTest {
    function test_stakeRevertsWhenNotStakeTracker() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.stake(stakeTracker, stakeAmount);
    }

    function test_StakesProperly() public {
        vm.prank(stakeTracker);
        rewarder.stake(stakeTracker, stakeAmount);

        assertEq(rewarder.balanceOf(stakeTracker), stakeAmount);
    }
}

contract DVRewarderWithdrawTest is DestinationVaultRewarderTest {
    function setUp() public override {
        super.setUp();

        vm.prank(stakeTracker);
        rewarder.stake(stakeTracker, stakeAmount);
    }

    function test_RevertWhenNotStakeTracker() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.withdraw(stakeTracker, stakeAmount, false);
    }

    function test_WithdrawsProperly() public {
        assertEq(rewarder.balanceOf(stakeTracker), stakeAmount);

        vm.prank(stakeTracker);
        rewarder.withdraw(stakeTracker, stakeAmount, false);

        assertEq(rewarder.balanceOf(stakeTracker), 0);
    }
}

contract DVRewarderGetRewardTest is DestinationVaultRewarderTest {
    function setUp() public override {
        super.setUp();

        rewardToken.mint(address(this), stakeAmount);
        rewardToken.approve(address(rewarder), stakeAmount);

        // Mock calls specifically for reward claiming.
        vm.mockCall(accessController, abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("accToke()"), abi.encode(makeAddr("ACC_TOKE")));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("toke()"), abi.encode(makeAddr("TOKE")));

        // Queue rewards.
        rewarder.queueNewRewards(stakeAmount);
    }

    function test_RevertsWhenNotStakeTracker() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        // Calling from `address(this)`.
        rewarder.getReward(stakeTracker, false);
    }

    function test_RewardsCanBeClaimed() public {
        // Check balances of reward token beforehand.
        assertEq(rewardToken.balanceOf(stakeTracker), 0);
        assertEq(rewardToken.balanceOf(address(rewarder)), stakeAmount);

        // Prank `stakeTracker`, stake on behalf of staker.
        vm.startPrank(stakeTracker);
        rewarder.stake(stakeTracker, stakeAmount);

        // Roll block duration + 1, will give staker all rewards.
        vm.roll(durationInBlock + 1);

        // Still pranked as `stakeTracker`,
        rewarder.getReward(stakeTracker, false);
        vm.stopPrank();

        // Check balances post operation.
        assertEq(rewardToken.balanceOf(stakeTracker), stakeAmount);
        assertEq(rewardToken.balanceOf(address(rewarder)), 0);
    }
}
