// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-line-length */

import { Test } from "forge-std/Test.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { RANDOM, WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";
import { MainRewarder } from "src/rewarders/MainRewarder.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

contract MainRewarderNotAbstract is MainRewarder {
    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bytes32 _rewardRole,
        bool _allowExtraRewards
    ) MainRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock, _rewardRole, _allowExtraRewards) { }

    function stake(address account, uint256 amount) external {
        _stake(account, amount);
    }

    function withdraw(address account, uint256 amount, bool claim) external {
        _withdraw(account, amount, claim);
    }

    function getReward(address account, address recipient, bool claimExtras) external {
        _getReward(account, recipient, claimExtras);
    }

    function canTokenBeRecovered(address) public pure override returns (bool) {
        return true;
    }
}

contract MainRewarderTest is Test {
    MainRewarderNotAbstract public rewarder;
    ERC20Mock public rewardToken;

    SystemRegistry public systemRegistry;
    AccessController public accessController;

    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 150_000;
    uint256 public totalSupply = 100;

    event ExtraRewardAdded(address reward);

    function setUp() public virtual {
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);
        rewarder = new MainRewarderNotAbstract(
            systemRegistry, address(rewardToken), newRewardRatio, durationInBlock, Roles.AUTO_POOL_REWARD_MANAGER, true
        );

        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_REWARD_MANAGER, address(this));
        accessController.grantRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));
    }
}

contract AddExtraReward is MainRewarderTest {
    function test_RevertIf_ExtraRewardNotAllowed() public {
        MainRewarderNotAbstract mainReward = new MainRewarderNotAbstract(
            systemRegistry, address(rewardToken), newRewardRatio, durationInBlock, Roles.AUTO_POOL_REWARD_MANAGER, false
        );

        vm.expectRevert(abi.encodeWithSignature("ExtraRewardsNotAllowed()"));
        mainReward.addExtraReward(makeAddr("EXTRA_REWARD"));
    }

    function test_RevertIf_ImproperRole_addExtraReward() public {
        vm.prank(makeAddr("NO_ROLE"));
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.addExtraReward(makeAddr("EXTRA_REWARD"));
    }

    function test_RevertIf_ExtraRewardIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "reward"));
        rewarder.addExtraReward(address(0));
    }

    function test_RevertIf_ItemExists() public {
        address extraReward = makeAddr("EXTRA_REWARD");
        rewarder.addExtraReward(extraReward);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        rewarder.addExtraReward(extraReward);
    }

    function test_RevertIf_MaxExtraRewardsReached() public {
        for (uint256 i = 0; i < 15; i++) {
            rewarder.addExtraReward(vm.addr(i + 1));
        }

        address extraReward = makeAddr("EXTRA_REWARD");
        vm.expectRevert(abi.encodeWithSelector(IMainRewarder.MaxExtraRewardsReached.selector));
        rewarder.addExtraReward(extraReward);
    }

    function test_EmitExtraRewardAddedEvent() public {
        address extraReward = makeAddr("EXTRA_REWARD");

        vm.expectEmit(true, true, true, true);
        emit ExtraRewardAdded(extraReward);
        rewarder.addExtraReward(extraReward);
    }

    function test_AddTheGivenExtraReward() public {
        assertEq(rewarder.extraRewardsLength(), 0, "extraRewardsLength before");
        rewarder.addExtraReward(makeAddr("EXTRA_REWARD"));
        assertEq(rewarder.extraRewardsLength(), 1, "extraRewardsLength after");
    }
}

contract Stake is MainRewarderTest {
    function test_IncreasesUsersBalancesAndTotalSupply() public {
        uint256 deposit = 1000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);
        rewarder.stake(user3, deposit);

        assertEq(rewarder.balanceOf(user1), deposit);
        assertEq(rewarder.balanceOf(user2), deposit);
        assertEq(rewarder.balanceOf(user3), deposit);

        assertEq(rewarder.totalSupply(), deposit * 3);
    }
}

contract Withdraw is MainRewarderTest {
    function test_DecreasesUsersBalancesAndTotalSupply() public {
        uint256 deposit = 1000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        // stake for 3 users
        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);
        rewarder.stake(user3, deposit);

        // withdraw for user3
        rewarder.withdraw(user3, deposit, false);

        assertEq(rewarder.balanceOf(user3), 0);
        assertEq(rewarder.totalSupply(), deposit * 2);
    }

    // Testing for edge cases.
    function test_QueueNewRewardsTwice_WhenNoSupply() public {
        rewardToken.mint(address(this), 100_000_000);

        uint256 newReward = 50_000_000;
        uint256 newReward2 = 50_000_000;

        rewardToken.approve(address(rewarder), newReward + newReward2);
        rewarder.queueNewRewards(newReward);
        uint256 rewardRateReward1 = rewarder.rewardRate();

        // advance the blockNumber by durationInBlock / 2 to simulate that the period is almost finished.
        vm.roll(block.number + durationInBlock / 2);

        rewarder.queueNewRewards(newReward2);

        uint256 currentRewards = rewarder.currentRewards();
        uint256 localDurationInBlock = rewarder.durationInBlock();

        assertEq(rewarder.historicalRewards(), newReward + newReward2, "historicalRewards");
        assertEq(rewarder.rewardPerTokenStored(), 0, "rewardPerTokenStored");

        uint256 finalReward = newReward2 + durationInBlock * rewardRateReward1;

        assertEq(currentRewards, finalReward, "currentRewards");
        assertEq(rewarder.rewardRate(), currentRewards / localDurationInBlock, "rewardRate");
    }

    function test_RewardDistributionForThreeUsersAtDifferentIntervals() public {
        uint256 deposit = 1000;
        uint256 totalRewards = 1_000_000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        // Divides the durationInBlock into 10 intervals (100,000 / 10,000)
        uint256 interval = 10_000;

        // Queue new rewards
        rewardToken.mint(address(this), totalRewards);
        rewardToken.approve(address(rewarder), totalRewards);
        rewarder.queueNewRewards(totalRewards);

        // Wait to 1/10 of the period (block.number + interval) with 0 totalSupply and let user1 and user2 stake
        vm.roll(block.number + interval);
        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);

        // Move to 3/10 of the period (block.number + 3 * interval) and let user3 stake
        vm.roll(block.number + 3 * interval);
        rewarder.stake(user3, deposit);

        // Capture the balance of users before the rewards are distributed
        uint256 balanceBeforeUser1 = rewardToken.balanceOf(user1);
        uint256 balanceBeforeUser2 = rewardToken.balanceOf(user2);
        uint256 balanceBeforeUser3 = rewardToken.balanceOf(user3);

        // Move to the end of the period (block.number + 10 * interval + 1)
        vm.roll(block.number + 10 * interval + 1);

        // Claim rewards for all users
        vm.prank(user1);
        rewarder.getReward();
        vm.prank(user2);
        rewarder.getReward();
        vm.prank(user3);
        rewarder.getReward();

        // Capture the distributed rewards
        uint256 user1Reward = rewardToken.balanceOf(user1) - balanceBeforeUser1;
        uint256 user2Reward = rewardToken.balanceOf(user2) - balanceBeforeUser2;
        uint256 user3Reward = rewardToken.balanceOf(user3) - balanceBeforeUser3;

        //The distributed rewards may get stuck depending upon the totalSupply, the stuck rewards are recovered after
        // the recovery duration
        assertLt(user1Reward + user2Reward + user3Reward, totalRewards, "Incorrect total rewards");
    }

    function test_QueueNewRewards_WhenNoSupply_And_Stake_After() public {
        rewardToken.mint(address(this), 100_000_000);

        uint256 newReward = 50_000_000;

        assertEq(rewarder.totalSupply(), 0, "totalSupply");
        rewardToken.approve(address(rewarder), newReward);
        rewarder.queueNewRewards(newReward);

        // Advance the blockNumber by durationInBlock / 2 to simulate that the period is almost finished.
        vm.roll(block.number + durationInBlock / 2);
        rewarder.stake(RANDOM, 1000);

        vm.roll(block.number + durationInBlock + 1);
        uint256 balanceBefore = rewardToken.balanceOf(RANDOM);
        uint256 rewardRate = rewarder.rewardRate();
        uint256 blocksStaked = durationInBlock / 2;
        vm.prank(RANDOM);
        rewarder.getReward();

        assertEq(rewardToken.balanceOf(RANDOM) - balanceBefore, rewardRate * blocksStaked, "Incorrect reward");
    }
}

contract Recover is MainRewarderTest {
    function test_RecoverStuckRewards() public {
        uint256 deposit = 1000;
        uint256 totalRewards = 1_000_000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        // Divides the durationInBlock into 10 intervals (100,000 / 10,000)
        uint256 interval = 10_000;

        // Queue new rewards
        rewardToken.mint(address(this), totalRewards);
        rewardToken.approve(address(rewarder), totalRewards);
        rewarder.queueNewRewards(totalRewards);

        // Wait to 1/10 of the period (block.number + interval) with 0 totalSupply and let user1 and user2 stake
        vm.roll(block.number + interval);
        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);

        // Move to 3/10 of the period (block.number + 3 * interval) and let user3 stake
        vm.roll(block.number + 3 * interval);
        rewarder.stake(user3, deposit);

        // Capture the balance of users before the rewards are distributed
        uint256 balanceBeforeUser1 = rewardToken.balanceOf(user1);
        uint256 balanceBeforeUser2 = rewardToken.balanceOf(user2);
        uint256 balanceBeforeUser3 = rewardToken.balanceOf(user3);

        // Move to the end of the period (block.number + 10 * interval + 1)
        vm.roll(block.number + 10 * interval + 1);

        // Claim rewards for all users
        vm.prank(user1);
        rewarder.getReward();
        vm.prank(user2);
        rewarder.getReward();
        vm.prank(user3);
        rewarder.getReward();

        // Capture the distributed rewards
        uint256 user1Reward = rewardToken.balanceOf(user1) - balanceBeforeUser1;
        uint256 user2Reward = rewardToken.balanceOf(user2) - balanceBeforeUser2;
        uint256 user3Reward = rewardToken.balanceOf(user3) - balanceBeforeUser3;

        assertLt(user1Reward + user2Reward + user3Reward, totalRewards, "Incorrect total rewards");

        if (user1Reward + user2Reward + user3Reward < totalRewards) {
            //ROLL OVER RECOVERY DURATION
            vm.roll(block.number + 31_536_000);
            uint256 beforeRecoverBal = rewardToken.balanceOf(address(this));
            rewarder.recover(address(rewardToken), address(this));
            uint256 afterRecoverBal = rewardToken.balanceOf(address(this));
            assertEq(
                afterRecoverBal - beforeRecoverBal,
                totalRewards - (user1Reward + user2Reward + user3Reward),
                "Incorrect recover amount"
            );
        }
    }
}
