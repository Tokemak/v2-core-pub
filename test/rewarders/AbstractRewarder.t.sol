/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IGPToke, GPToke } from "src/staking/GPToke.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";

import { AbstractRewarder } from "src/rewarders/AbstractRewarder.sol";

import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";

import { Roles } from "src/libs/Roles.sol";

import { Errors } from "src/utils/Errors.sol";

import { RANDOM, WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";

contract Rewarder is AbstractRewarder {
    error NotImplemented();

    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock
    ) AbstractRewarder(_systemRegistry, _stakeTracker, _rewardToken, _newRewardRatio, _durationInBlock) { }

    function getReward() external pure override {
        revert NotImplemented();
    }

    function exposed_getRewardWrapper(address account) external {
        _getReward(account);
    }

    function exposed_updateReward(address account) external {
        _updateReward(account);
    }

    function stake(address account, uint256 amount) external override {
        _stake(account, amount);
    }

    /// @dev This function is used to test the onlyWhitelisted modifier.
    function useOnlyWhitelisted() external view onlyWhitelisted returns (bool) {
        return true;
    }

    /// @dev This function is used to test the onlyStakeTracker modifier.
    function useOnlyStakeTracker() external view onlyStakeTracker returns (bool) {
        return true;
    }

    function exposed_notifyRewardAmount(uint256 reward) external {
        notifyRewardAmount(reward);
    }

    function withdraw(address account, uint256 amount) external {
        _withdraw(account, amount);
    }
}

contract AbstractRewarderTest is Test {
    address public operator;
    address public liquidator;

    Rewarder public rewarder;
    ERC20Mock public rewardToken;

    address public stakeTracker;
    SystemRegistry public systemRegistry;

    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 100;
    uint256 public totalSupply = 100;

    event AddedToWhitelist(address indexed wallet);
    event RemovedFromWhitelist(address indexed wallet);
    event QueuedRewardsUpdated(uint256 startingQueuedRewards, uint256 startingNewRewards, uint256 queuedRewards);
    event NewRewardRateUpdated(uint256 newRewardRate);
    event RewardAdded(
        uint256 reward,
        uint256 rewardRate,
        uint256 lastUpdateBlock,
        uint256 periodInBlockFinish,
        uint256 historicalRewards
    );
    event RewardDurationUpdated(uint256 rewardDuration);
    event TokeLockDurationUpdated(uint256 newDuration);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event UserRewardUpdated(
        address indexed user, uint256 amount, uint256 rewardPerTokenStored, uint256 lastUpdateBlock
    );

    function setUp() public {
        // fork mainnet so we have TOKE deployed
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        operator = vm.addr(1);
        liquidator = vm.addr(2);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.DV_REWARD_MANAGER_ROLE, operator);
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, liquidator);

        stakeTracker = vm.addr(12);
        // mock stake tracker totalSupply function by default
        vm.mockCall(
            address(stakeTracker), abi.encodeWithSelector(IBaseRewarder.totalSupply.selector), abi.encode(totalSupply)
        );

        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );
        rewarder = new Rewarder(
            systemRegistry,
            address(stakeTracker),
            address(rewardToken),
            newRewardRatio,
            durationInBlock
        );

        // mint reward token to liquidator
        rewardToken.mint(liquidator, 100_000_000_000);

        // liquidator grants a large allowance to the rewarder contract for tests that use `queueNewRewards`.
        // In tests that require 0 allowance, we decrease the allowance accordingly.
        vm.prank(liquidator);
        rewardToken.approve(address(rewarder), 100_000_000_000);

        vm.label(operator, "operator");
        vm.label(liquidator, "liquidator");
        vm.label(RANDOM, "RANDOM");
        vm.label(TOKE_MAINNET, "TOKE_MAINNET");
        vm.label(address(systemRegistry), "systemRegistry");
        vm.label(address(accessController), "accessController");
        vm.label(address(stakeTracker), "stakeTracker");
        vm.label(address(rewarder), "rewarder");
    }

    /**
     * @dev Runs a default scenario that can be used for testing.
     * The scenario assumes being halfway through the rewards period (50 out of 100 blocks) with a distribution of 50
     * rewards tokens.
     * The user has 10% of the total supply of staked tokens, resulting in an earned reward of 10% of the distributed
     * rewards.
     * The expected earned reward for the user at this point is 5 tokens.
     * This function does not test anything, but provides a predefined scenario for testing purposes.
     * @return The expected earned reward for the user in the default scenario => 5
     */
    function _runDefaultScenario() internal returns (uint256) {
        uint256 balance = 10;
        uint256 newReward = 100;

        vm.startPrank(liquidator);
        rewardToken.approve(address(rewarder), 100_000_000_000);
        rewarder.queueNewRewards(newReward);

        vm.mockCall(
            address(stakeTracker), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(balance)
        );

        // go to the middle of the period
        vm.roll(block.number + durationInBlock / 2);

        return 5;
    }

    /**
     * @dev Sets up a GPToke contract in the system registry.
     *  Mostly used for testing purposes.
     * @return The address of the GPToke contract.
     */
    function _setupGpTokeAndTokeRewarder() internal returns (GPToke) {
        uint256 minStakingDuration = 30 days;

        GPToke gpToke = new GPToke(
            systemRegistry,
            //solhint-disable-next-line not-rely-on-time
            block.timestamp, // start epoch
            minStakingDuration
        );

        systemRegistry.setGPToke(address(gpToke));

        // replace the rewarder by a new one with TOKE
        rewarder = new Rewarder(
            systemRegistry,
            address(stakeTracker),
            TOKE_MAINNET,
            newRewardRatio,
            durationInBlock
        );

        // send 1_000_000_000 TOKE to liquidator for tests where reward token is TOKE
        deal(TOKE_MAINNET, liquidator, 1_000_000_000);

        vm.prank(liquidator);
        IERC20(TOKE_MAINNET).approve(address(rewarder), 100_000_000_000);

        return gpToke;
    }
}

contract OnlyStakeTracker is AbstractRewarderTest {
    function test_RevertIf_SenderIsNotStakeTracker() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        rewarder.useOnlyStakeTracker();
    }

    function test_AllowStakeTracker() public {
        vm.prank(address(stakeTracker));
        bool res = rewarder.useOnlyStakeTracker();
        assertTrue(res);
    }
}

contract OnlyWhitelisted is AbstractRewarderTest {
    function test_RevertIf_SenderIsNeitherWhitelistedOrLiquidator() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        rewarder.useOnlyWhitelisted();
    }

    function test_AllowWhitelistedWallet() public {
        vm.prank(operator);
        rewarder.addToWhitelist(RANDOM);

        vm.prank(RANDOM);
        bool res = rewarder.useOnlyWhitelisted();

        assertTrue(res);
    }

    function test_AllowLiquidator() public {
        vm.prank(liquidator);
        bool res = rewarder.useOnlyWhitelisted();

        assertTrue(res);
    }
}

contract Constructor is AbstractRewarderTest {
    function test_RevertIf_StakeTrackerIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_stakeTracker"));

        new Rewarder(
            systemRegistry,
            address(0),
            address(1),
            newRewardRatio,
            durationInBlock
        );
    }

    function test_RevertIf_RewardTokenIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_rewardToken"));

        new Rewarder(
            systemRegistry,
            address(1),
            address(0),
            newRewardRatio,
            durationInBlock
        );
    }
}

contract AddToWhitelist is AbstractRewarderTest {
    function test_RevertIf_ZeroAddressGiven() public {
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "wallet"));
        rewarder.addToWhitelist(address(0));
    }

    function test_RevertIf_AlreadyRegistered() public {
        vm.startPrank(operator);
        rewarder.addToWhitelist(RANDOM);
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        rewarder.addToWhitelist(RANDOM);
    }

    function test_AddWalletToWhitelist() public {
        vm.prank(operator);
        rewarder.addToWhitelist(RANDOM);
        bool val = rewarder.isWhitelisted(RANDOM);
        assertTrue(val);
    }

    function test_EmitAddedToWhitelistEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AddedToWhitelist(RANDOM);

        vm.prank(operator);
        rewarder.addToWhitelist(RANDOM);
    }
}

contract RemoveFromWhitelist is AbstractRewarderTest {
    function test_RevertIf_NotRegistered() public {
        vm.startPrank(operator);

        rewarder.addToWhitelist(RANDOM);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        rewarder.removeFromWhitelist(address(1));
    }

    function test_RemoveWhitelistedWallet() public {
        vm.startPrank(operator);

        rewarder.addToWhitelist(RANDOM);
        rewarder.removeFromWhitelist(RANDOM);

        bool val = rewarder.isWhitelisted(RANDOM);
        assertFalse(val);
    }

    function test_EmitRemovedFromWhitelistEvent() public {
        vm.startPrank(operator);
        rewarder.addToWhitelist(RANDOM);

        vm.expectEmit(true, true, true, true);
        emit RemovedFromWhitelist(RANDOM);
        rewarder.removeFromWhitelist(RANDOM);
    }
}

contract IsWhitelisted is AbstractRewarderTest {
    function test_ReturnTrueIfWalletIsWhitelisted() public {
        vm.prank(operator);
        rewarder.addToWhitelist(RANDOM);

        bool val = rewarder.isWhitelisted(RANDOM);
        assertTrue(val);
    }

    function test_ReturnFalseIfWalletIsNotWhitelisted() public {
        bool val = rewarder.isWhitelisted(RANDOM);
        assertFalse(val);
    }
}

contract QueueNewRewards is AbstractRewarderTest {
    function test_RevertIf_SenderIsNotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        rewarder.queueNewRewards(100_000_000);
    }

    function test_RevertIf_SenderDidntGrantRewarder() public {
        vm.startPrank(liquidator);

        rewardToken.approve(address(rewarder), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        rewarder.queueNewRewards(100_000_000);
    }

    function test_SetQueuedRewardsToZeroWhen_PeriodIsFinished() public {
        vm.startPrank(liquidator);

        vm.expectEmit(true, true, true, true);
        emit QueuedRewardsUpdated(0, 100_000_000, 0);

        rewarder.queueNewRewards(100_000_000);
    }

    function test_SetQueuedRewardsToZeroWhen_PeriodIsNotFinished() public {
        uint256 newReward = 100_000_000;
        vm.startPrank(liquidator);
        rewarder.queueNewRewards(newReward);

        // advance the blockNumber by durationInBlock / 2 to simulate that the period is almost finished.
        vm.roll(block.number + durationInBlock / 2);

        vm.expectEmit(true, true, true, true);
        emit QueuedRewardsUpdated(0, newReward, 0);
        rewarder.queueNewRewards(newReward);
    }

    function test_QueueNewRewardsWhen_AccruedRewardsAreLargeComparedToNewRewards() public {
        uint256 newReward = 100_000_000;
        vm.startPrank(liquidator);
        rewarder.queueNewRewards(newReward);

        // advance the blockNumber by durationInBlock / 2 to simulate that the period is almost finished.
        vm.roll(block.number + durationInBlock / 2);

        uint256 newRewardBatch2 = newReward / 10;
        vm.expectEmit(true, true, true, true);
        emit QueuedRewardsUpdated(0, newRewardBatch2, newRewardBatch2);
        rewarder.queueNewRewards(newRewardBatch2);
    }
}

contract SetNewRewardRate is AbstractRewarderTest {
    function test_RevertIf_SenderIsNotRewardManager() public {
        uint256 newRewardRatio = 10;
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.setNewRewardRate(newRewardRatio);
    }

    function test_UpdateNewRewardRatio() public {
        uint256 newRewardRatio = 10;

        vm.prank(operator);
        rewarder.setNewRewardRate(newRewardRatio);

        assertEq(newRewardRatio, rewarder.newRewardRatio());
    }

    function test_EmitNewRewardRateUpdated() public {
        uint256 newRewardRatio = 10;

        vm.expectEmit(true, true, true, true);
        emit NewRewardRateUpdated(newRewardRatio);

        vm.prank(operator);
        rewarder.setNewRewardRate(newRewardRatio);
    }
}

contract TotalSupply is AbstractRewarderTest {
    function test_ReturnStakeTrackerTotalSupply() public {
        uint256 result = rewarder.totalSupply();

        assertEq(result, totalSupply);
    }
}

contract BalanceOf is AbstractRewarderTest {
    function test_ReturnBalanceOfUserInStakeTracker() public {
        uint256 balanceOf = 100;

        vm.mockCall(
            address(stakeTracker), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(balanceOf)
        );

        uint256 result = rewarder.balanceOf(RANDOM);

        assertEq(result, balanceOf);
    }
}

contract LastBlockRewardApplicable is AbstractRewarderTest {
    function test_ReturnBlockNumberIfPeriodIsNotFinished() public {
        vm.startPrank(liquidator);
        rewarder.queueNewRewards(100_000_000);

        uint256 result = rewarder.lastBlockRewardApplicable();

        assertEq(result, block.number);
    }

    function test_ReturnPeriodinblockfinishIfPeriodIsFinished() public {
        uint256 result = rewarder.lastBlockRewardApplicable();

        assertEq(result, 0);
    }
}

contract RewardPerToken is AbstractRewarderTest {
    function test_ReturnRewardpertokentstoredWhen_TotalSupplyIsEq_0() public {
        uint256 result = rewarder.rewardPerToken();
        uint256 rewardPerTokenStored = rewarder.rewardPerTokenStored();

        assertEq(result, rewardPerTokenStored);
    }

    function test_ReturnMoreThanRewardpertokentstoredValueWhen_TotalSupplyIsGt_0() public {
        uint256 result = rewarder.rewardPerToken();
        uint256 rewardPerTokenStored = rewarder.rewardPerTokenStored();

        assertEq(result, rewardPerTokenStored);
    }
}

contract Earned is AbstractRewarderTest {
    function test_CalculateEarnedRewardsForGivenWallet() public {
        uint256 expectedRewards = _runDefaultScenario();

        uint256 earned = rewarder.earned(RANDOM);

        assertEq(earned, expectedRewards);
    }
}

contract SetDurationInBlock is AbstractRewarderTest {
    function test_RevertIf_SenderIsNotRewardManager() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.setDurationInBlock(newRewardRatio);
    }

    function test_UpdateDurationInBlock() public {
        uint256 durationInBlock = 200;

        vm.prank(operator);
        rewarder.setDurationInBlock(durationInBlock);

        assertEq(durationInBlock, rewarder.durationInBlock());
    }

    function test_EmitRewardDurationUpdated() public {
        uint256 durationInBlock = 200;

        vm.expectEmit(true, true, true, true);
        emit RewardDurationUpdated(durationInBlock);

        vm.prank(operator);
        rewarder.setDurationInBlock(durationInBlock);
    }
}

contract NotifyRewardAmount is AbstractRewarderTest {
    function test_EmitRewardAdded() public {
        uint256 newReward = 100;
        _runDefaultScenario();

        vm.expectEmit(true, true, true, true);
        emit RewardAdded(
            newReward + newReward / 2,
            newReward / durationInBlock,
            block.number,
            block.number + durationInBlock,
            newReward * 2
        );

        vm.startPrank(operator);
        rewarder.exposed_notifyRewardAmount(newReward);
        vm.stopPrank();
    }
}

contract _updateReward is AbstractRewarderTest {
    function test_EmitRewardAdded() public {
        uint256 expectedReward = _runDefaultScenario();

        uint256 rewardPerTokenStored = rewarder.rewardPerToken();

        vm.expectEmit(true, true, true, true);
        emit UserRewardUpdated(RANDOM, expectedReward, rewardPerTokenStored, block.number);

        rewarder.exposed_updateReward(RANDOM);
    }
}

contract SetTokeLockDuration is AbstractRewarderTest {
    function test_RevertIf_SenderIsNotRewardManager() public {
        uint256 tokeLockDuration = 200;
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.setTokeLockDuration(tokeLockDuration);
    }

    function test_RevertWhen_GptokeIsNotSet() public {
        vm.startPrank(operator);

        uint256 tokeLockDuration = 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gpToke"));
        rewarder.setTokeLockDuration(tokeLockDuration);
    }

    function test_RevertWhen_StakingDurationIsTooShort() public {
        _setupGpTokeAndTokeRewarder();

        vm.startPrank(operator);
        uint256 tokeLockDuration = 1;
        vm.expectRevert(abi.encodeWithSelector(IGPToke.StakingDurationTooShort.selector));
        rewarder.setTokeLockDuration(tokeLockDuration);
    }

    function test_TurnOffFunctionalityWhen_DurationIs_0() public {
        vm.startPrank(operator);

        uint256 tokeLockDuration = 0;
        rewarder.setTokeLockDuration(tokeLockDuration);
        assertEq(tokeLockDuration, rewarder.tokeLockDuration());
    }

    function test_EmitTokeLockDurationUpdatedEvent() public {
        vm.startPrank(operator);

        uint256 tokeLockDuration = 0;
        vm.expectEmit(true, true, true, true);
        emit TokeLockDurationUpdated(tokeLockDuration);
        rewarder.setTokeLockDuration(tokeLockDuration);
    }
}

contract _stake is AbstractRewarderTest {
    function test_RevertIf_AccountIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "account"));
        rewarder.stake(address(0), 100);
    }

    function test_RevertIf_AmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amount"));
        rewarder.stake(address(1), 0);
    }

    function test_EmitStakedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Staked(address(1), 100);

        rewarder.stake(address(1), 100);
    }
}

contract _withdraw is AbstractRewarderTest {
    function test_RevertIf_AccountIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "account"));
        rewarder.withdraw(address(0), 100);
    }

    function test_RevertIf_AmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amount"));
        rewarder.withdraw(address(1), 0);
    }

    function test_EmitWithdrawnEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(address(1), 100);

        rewarder.withdraw(address(1), 100);
    }
}

contract _getReward is AbstractRewarderTest {
    function test_RevertIf_AccountIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "account"));
        rewarder.exposed_getRewardWrapper(address(0));
    }

    function test_TransferRewardsToUser() public {
        uint256 expectedRewards = _runDefaultScenario();

        uint256 balanceBefore = rewardToken.balanceOf(RANDOM);
        rewarder.exposed_getRewardWrapper(RANDOM);
        uint256 balanceAfter = rewardToken.balanceOf(RANDOM);

        assertEq(balanceAfter - balanceBefore, expectedRewards);
    }

    function test_EmitRewardPaidEvent() public {
        uint256 expectedRewards = _runDefaultScenario();

        vm.expectEmit(true, true, true, true);
        emit RewardPaid(RANDOM, expectedRewards);

        rewarder.exposed_getRewardWrapper(RANDOM);
    }

    // @dev see above for doc: for gpToke amounts had to be bumped up due to new mins
    function _runDefaultScenarioGpToke() internal returns (uint256) {
        uint256 balance = 1000;
        uint256 newReward = 50_000;

        deal(TOKE_MAINNET, address(rewarder), 100_000_000_000);

        vm.startPrank(liquidator);
        rewardToken.approve(address(rewarder), 100_000_000_000);
        rewarder.queueNewRewards(newReward);

        vm.mockCall(
            address(stakeTracker), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(balance)
        );

        // go to the middle of the period
        vm.roll(block.number + durationInBlock / 2);

        return 5;
    }

    function test_StakeRewardsToGptTokeWhenRewardTokenIsTokeAndFeatureIsEnabled() public {
        GPToke gPToke = _setupGpTokeAndTokeRewarder();
        _runDefaultScenarioGpToke();

        vm.startPrank(operator);
        rewarder.setTokeLockDuration(30 days);
        vm.stopPrank();

        uint256 balanceBefore = gPToke.balanceOf(RANDOM);
        rewarder.exposed_getRewardWrapper(RANDOM);
        uint256 balanceAfter = gPToke.balanceOf(RANDOM);

        assertTrue(balanceAfter > balanceBefore);
    }
}
