// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { DestinationVaultMainRewarder, MainRewarder } from "src/rewarders/DestinationVaultMainRewarder.sol";
import { ExtraRewarder } from "src/rewarders/ExtraRewarder.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { StakeTrackingMock } from "test/mocks/StakeTrackingMock.sol";
import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";
import { Roles } from "src/libs/Roles.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { Errors } from "src/utils/Errors.sol";
import { PRANK_ADDRESS, RANDOM } from "test/utils/Addresses.sol";

/**
 * @notice This contract is an integration test suite for the MainRewarder.sol and ExtraRewarder.sol contracts.
 * It aims to test the interaction between these contracts.
 * Detailed unit tests for common functionalities of rewarder types are performed in the AbstractRewarderTest.
 */
contract MainRewarderTest is BaseTest {
    address private operator;

    StakeTrackingMock private stakeTracker;
    address private liquidator;

    event TokeLockDurationUpdated(uint256 newDuration);

    event ExtraRewardAdded(address reward);
    event ExtraRewardsCleared();

    MainRewarder private mainRewardVault;
    ExtraRewarder private extraReward1Vault;
    ExtraRewarder private extraReward2Vault;

    ERC20Mock private mainReward;
    ERC20Mock private extraReward1;
    ERC20Mock private extraReward2;

    uint256 private amount = 100_000;
    uint256 private newRewardRatio = 800;
    uint256 private durationInBlock = 100;
    uint256 public tokeMinStakeAmount = 10_000;

    function setUp() public virtual override(BaseTest) {
        BaseTest.setUp();

        operator = vm.addr(1);
        liquidator = vm.addr(2);
        mainReward = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);
        extraReward1 = new ERC20Mock("EXTRA_REWARD_1", "EXTRA_REWARD_1", address(this), 0);
        extraReward2 = new ERC20Mock("EXTRA_REWARD_2", "EXTRA_REWARD_2", address(this), 0);

        // grant new roles
        accessController.grantRole(Roles.DV_REWARD_MANAGER_ROLE, operator);
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, liquidator);

        deployAccToke();

        stakeTracker = new StakeTrackingMock();

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        mainRewardVault = MainRewarder(
            new DestinationVaultMainRewarder(
                systemRegistry, address(stakeTracker), address(mainReward), newRewardRatio, durationInBlock, true
            )
        );

        extraReward1Vault = new ExtraRewarder(
            systemRegistry, address(extraReward1), address(mainRewardVault), newRewardRatio, durationInBlock
        );

        extraReward2Vault = new ExtraRewarder(
            systemRegistry, address(extraReward2), address(mainRewardVault), newRewardRatio, durationInBlock
        );

        mainReward.mint(liquidator, amount);
        extraReward1.mint(liquidator, amount * 10);
        extraReward2.mint(liquidator, amount * 10);

        // make sure only liquidator has access to `queueNewRewards`
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(operator);
        mainRewardVault.queueNewRewards(amount);

        vm.startPrank(liquidator);
        IERC20(mainReward).approve(address(mainRewardVault), amount);
        mainRewardVault.queueNewRewards(amount);

        IERC20(extraReward1).approve(address(extraReward1Vault), amount);
        extraReward1Vault.queueNewRewards(amount);

        IERC20(extraReward2).approve(address(extraReward2Vault), amount);
        extraReward2Vault.queueNewRewards(amount);

        vm.startPrank(operator);
        mainRewardVault.addExtraReward(address(extraReward1Vault));
        mainRewardVault.addExtraReward(address(extraReward2Vault));

        vm.stopPrank();

        vm.label(operator, "operator");
        vm.label(liquidator, "liquidator");
        vm.label(address(toke), "toke");
        vm.label(address(mainRewardVault), "mainRewardVault");
        vm.label(address(extraReward1Vault), "extraReward1Vault");
        vm.label(address(extraReward2Vault), "extraReward2Vault");
    }

    function test_addExtraReward_EmitsExtraRewardAddedEvent() public {
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true);
        emit ExtraRewardAdded(address(7));
        mainRewardVault.addExtraReward(address(7));
        vm.stopPrank();
    }

    function test_clearExtraRewards_EmitsExtraRewardsClearedEvent() public {
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true);
        emit ExtraRewardsCleared();
        mainRewardVault.clearExtraRewards();
        vm.stopPrank();
    }

    function test_getAllRewards() public {
        vm.prank(address(stakeTracker));
        mainRewardVault.stake(RANDOM, amount);

        vm.roll(block.number + 100);

        uint256 earned = mainRewardVault.earned(RANDOM);
        assertEq(earned, amount);

        uint256 rewardBalanceBefore = mainReward.balanceOf(RANDOM);
        uint256 extraReward1BalanceBefore = extraReward1.balanceOf(RANDOM);
        uint256 extraReward2BalanceBefore = extraReward2.balanceOf(RANDOM);

        vm.prank(RANDOM);
        mainRewardVault.getReward();

        uint256 rewardBalanceAfter = mainReward.balanceOf(RANDOM);
        uint256 extraReward1BalanceAfter = extraReward1.balanceOf(RANDOM);
        uint256 extraReward2BalanceAfter = extraReward2.balanceOf(RANDOM);

        assertEq(rewardBalanceAfter - rewardBalanceBefore, amount);
        assertEq(extraReward1BalanceAfter - extraReward1BalanceBefore, amount);
        assertEq(extraReward2BalanceAfter - extraReward2BalanceBefore, amount);
    }

    function test_toke_autoStakeRewards() public {
        _runTokeStakingTest(30 days, 0, true);
    }

    function test_toke_notAutoStakeRewards() public {
        _runTokeStakingTest(0, amount, false);
    }

    // This one covers Sherlock 217-M:
    // https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/217-M/565-best.md
    function test_toke_getExtraRewards_WhenTokeRewardIsLessThanMinStake() public {
        // setup toke rewarder
        MainRewarder tokeRewarder = MainRewarder(
            new DestinationVaultMainRewarder(
                systemRegistry, address(stakeTracker), address(toke), newRewardRatio, durationInBlock, true
            )
        );
        vm.prank(address(operator));
        tokeRewarder.setTokeLockDuration(30 days);

        // and some extra rewarders
        extraReward1Vault = new ExtraRewarder(
            systemRegistry, address(extraReward1), address(tokeRewarder), newRewardRatio, durationInBlock
        );
        extraReward2Vault = new ExtraRewarder(
            systemRegistry, address(extraReward2), address(tokeRewarder), newRewardRatio, durationInBlock
        );
        vm.startPrank(operator);
        tokeRewarder.addExtraReward(address(extraReward1Vault));
        tokeRewarder.addExtraReward(address(extraReward2Vault));
        vm.stopPrank();

        // use small amount to get rewards that are < tokeMinStakeAmount
        amount = 100;

        // load available extra rewards
        vm.startPrank(liquidator);
        IERC20(extraReward1).approve(address(extraReward1Vault), amount);
        extraReward1Vault.queueNewRewards(amount);

        IERC20(extraReward2).approve(address(extraReward2Vault), amount);
        extraReward2Vault.queueNewRewards(amount);
        vm.stopPrank();

        // load toke rewards
        deal(address(toke), liquidator, 100_000_000_000);
        vm.startPrank(liquidator);
        IERC20(address(toke)).approve(address(tokeRewarder), amount);
        tokeRewarder.queueNewRewards(amount);
        vm.stopPrank();

        // stake
        vm.prank(address(stakeTracker));
        tokeRewarder.stake(RANDOM, amount);

        // let some time pass
        vm.roll(block.number + 100);

        // ensure we got less toke rewards than min stake amount
        assertTrue(tokeRewarder.earned(RANDOM) < tokeMinStakeAmount);

        // record balances before
        uint256 tokeBalanceBefore = toke.balanceOf(RANDOM);
        uint256 accTokeBalanceBefore = accToke.balanceOf(RANDOM);
        uint256 extraReward1BalanceBefore = extraReward1.balanceOf(RANDOM);
        uint256 extraReward2BalanceBefore = extraReward2.balanceOf(RANDOM);

        // claim rewards
        vm.prank(RANDOM);
        tokeRewarder.getReward();

        // validate balances after – toke should be the same as before
        assertEq(toke.balanceOf(RANDOM), tokeBalanceBefore);
        assertEq(accToke.balanceOf(RANDOM), accTokeBalanceBefore);
        // extra rewards should be claimed successfully
        assertTrue(extraReward1.balanceOf(RANDOM) > extraReward1BalanceBefore);
        assertTrue(extraReward2.balanceOf(RANDOM) > extraReward2BalanceBefore);
    }

    function _runTokeStakingTest(
        uint256 stakeDuration,
        uint256 expectedTokeBalanceDiff,
        bool accTokeIncreaseExpected
    ) private {
        MainRewarder tokeRewarder = MainRewarder(
            new DestinationVaultMainRewarder(
                systemRegistry, address(stakeTracker), address(toke), newRewardRatio, durationInBlock, true
            )
        );

        // set duration
        vm.prank(address(operator));
        vm.expectEmit(true, false, false, false);
        emit TokeLockDurationUpdated(stakeDuration);
        tokeRewarder.setTokeLockDuration(stakeDuration);

        // load available rewards
        deal(address(toke), liquidator, 100_000_000_000);
        vm.startPrank(liquidator);
        IERC20(address(toke)).approve(address(tokeRewarder), amount);
        tokeRewarder.queueNewRewards(amount);
        vm.stopPrank();

        vm.prank(address(stakeTracker));
        tokeRewarder.stake(RANDOM, amount);

        vm.roll(block.number + 100);

        uint256 earned = tokeRewarder.earned(RANDOM);
        assertEq(earned, amount);

        uint256 tokeBalanceBefore = toke.balanceOf(RANDOM);
        uint256 accTokeBalanceBefore = accToke.balanceOf(RANDOM);

        // claim rewards

        vm.prank(RANDOM);
        tokeRewarder.getReward();

        assertEq(toke.balanceOf(RANDOM) - tokeBalanceBefore, expectedTokeBalanceDiff);
        assertEq(accToke.balanceOf(RANDOM) > accTokeBalanceBefore, accTokeIncreaseExpected);
    }
}
