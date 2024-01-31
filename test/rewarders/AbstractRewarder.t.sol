/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IAccToke, AccToke } from "src/staking/AccToke.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";

import { AbstractRewarder } from "src/rewarders/AbstractRewarder.sol";

import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";

import { Roles } from "src/libs/Roles.sol";

import { Errors } from "src/utils/Errors.sol";

import { RANDOM, WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";

contract Rewarder is AbstractRewarder {
    error NotImplemented();

    uint256 internal _mockBalanceOf;
    uint256 internal _mockTotalSupply;

    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bytes32 _rewardRole
    ) AbstractRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock, _rewardRole) { }

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
        _stakeAbstractRewarder(account, amount);
    }

    /// @dev This function is used to test the onlyWhitelisted modifier.
    function useOnlyWhitelisted() external view onlyWhitelisted returns (bool) {
        return true;
    }

    function exposed_notifyRewardAmount(uint256 reward) external {
        notifyRewardAmount(reward);
    }

    function withdraw(address account, uint256 amount) external {
        _withdrawAbstractRewarder(account, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return _mockTotalSupply;
    }

    function balanceOf(address) public view override returns (uint256) {
        return _mockBalanceOf;
    }

    /// we can't mock internal calls, so we expose them using following functions
    function setBalanceOf(uint256 balance) external {
        _mockBalanceOf = balance;
    }

    function setTotalSupply(uint256 mockTotalSupply) external {
        _mockTotalSupply = mockTotalSupply;
    }
}

contract AbstractRewarderTest is Test {
    address public operator;
    address public liquidator;

    Rewarder public rewarder;
    ERC20Mock public rewardToken;

    SystemRegistry public systemRegistry;

    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 100;
    uint256 public totalSupply = 100;
    uint256 public tokeMinStakeAmount = 10_000;

    event AddedToWhitelist(address indexed wallet);
    event RemovedFromWhitelist(address indexed wallet);
    event QueuedRewardsUpdated(uint256 startingQueuedRewards, uint256 startingNewRewards, uint256 queuedRewards);
    event RewardAdded(
        uint256 reward,
        uint256 rewardRate,
        uint256 lastUpdateBlock,
        uint256 periodInBlockFinish,
        uint256 historicalRewards
    );
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

        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );
        rewarder = new Rewarder(
            systemRegistry, address(rewardToken), newRewardRatio, durationInBlock, Roles.DV_REWARD_MANAGER_ROLE
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

        // mock rewarder balanceOf function
        rewarder.setBalanceOf(balance);

        // go to the middle of the period
        vm.roll(block.number + durationInBlock / 2);

        rewarder.setTotalSupply(totalSupply);

        return 5;
    }

    /**
     * @dev Sets up a AccToke contract in the system registry.
     *  Mostly used for testing purposes.
     * @return The address of the AccToke contract.
     */
    function _setupAccTokeAndTokeRewarder() internal returns (AccToke) {
        uint256 minStakingDuration = 30 days;

        AccToke accToke = new AccToke(
            systemRegistry,
            //solhint-disable-next-line not-rely-on-time
            block.timestamp, // start epoch
            minStakingDuration
        );

        systemRegistry.setAccToke(address(accToke));

        // replace the rewarder by a new one with TOKE
        rewarder =
            new Rewarder(systemRegistry, TOKE_MAINNET, newRewardRatio, durationInBlock, Roles.DV_REWARD_MANAGER_ROLE);

        // send 1_000_000_000 TOKE to liquidator for tests where reward token is TOKE
        deal(TOKE_MAINNET, liquidator, 1_000_000_000);

        vm.prank(liquidator);
        IERC20(TOKE_MAINNET).approve(address(rewarder), 100_000_000_000);

        return accToke;
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
    function test_RevertIf_RewardTokenIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_rewardToken"));

        new Rewarder(systemRegistry, address(0), newRewardRatio, durationInBlock, Roles.DV_REWARD_MANAGER_ROLE);
    }

    function test_RevertIf_DurationInBlockIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "_durationInBlock"));

        new Rewarder(systemRegistry, address(1), newRewardRatio, 0, Roles.DV_REWARD_MANAGER_ROLE);
    }

    function test_RevertIf_NewRewardRatioIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "_newRewardRatio"));

        new Rewarder(systemRegistry, address(1), 0, durationInBlock, Roles.DV_REWARD_MANAGER_ROLE);
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

    /**
     * @dev
     * This test ensures that after fixing the logic error in the `queueNewRewards` function,
     * the right amount of tokens is transferred from the sender even if `queuedRewards` is not 0.
     * Previously, the call either reverted or more funds were pulled than they should have.
     * audit report: https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/012-H/379-best.md
     */
    function test_TransfersCorrectAmount() public {
        vm.startPrank(liquidator);

        // Reset approvals to start from a clean slate.
        rewardToken.approve(address(rewarder), 0);

        // Set up a scenario where `queuedRewards` ends up being non-zero.
        // Approving only what's needed for each step to prevent any excess transfers.
        rewardToken.approve(address(rewarder), 100_000_000);
        rewarder.queueNewRewards(100_000_000);
        vm.roll(block.number + durationInBlock / 2);
        rewardToken.approve(address(rewarder), 1000);
        rewarder.queueNewRewards(1000);
        vm.roll(block.number + durationInBlock / 2);

        // Assert that `queuedRewards` is not zero, confirming our setup.
        assertEq(rewarder.queuedRewards(), 1000);

        // Test the fixed logic by checking the token transfer amounts.
        uint256 balanceBefore = rewardToken.balanceOf(liquidator);
        rewardToken.approve(address(rewarder), 1000);
        rewarder.queueNewRewards(1000);
        uint256 balanceAfter = rewardToken.balanceOf(liquidator);

        // Validate that only the expected amount is transferred.
        assertEq(balanceBefore - balanceAfter, 1000);

        vm.stopPrank();
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

    function test_RevertWhen_AccTokeIsNotSet() public {
        vm.startPrank(operator);

        uint256 tokeLockDuration = 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "accToke"));
        rewarder.setTokeLockDuration(tokeLockDuration);
    }

    function test_RevertWhen_StakingDurationIsTooShort() public {
        _setupAccTokeAndTokeRewarder();

        vm.startPrank(operator);
        uint256 tokeLockDuration = 1;
        vm.expectRevert(abi.encodeWithSelector(IAccToke.StakingDurationTooShort.selector));
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

    // @dev see above for doc: for accToke amounts had to be bumped up due to new mins
    function _runDefaultScenarioAccToke() internal returns (uint256) {
        uint256 newReward = 50_000;

        deal(TOKE_MAINNET, address(rewarder), 100_000_000_000);

        vm.startPrank(liquidator);
        rewardToken.approve(address(rewarder), 100_000_000_000);
        rewarder.queueNewRewards(newReward);

        // go to the middle of the period
        vm.roll(block.number + durationInBlock / 2);

        rewarder.setTotalSupply(totalSupply);

        return 5;
    }

    function test_StakeRewardsToAccTokeWhenRewardTokenIsTokeAndFeatureIsEnabled() public {
        AccToke accToke = _setupAccTokeAndTokeRewarder();
        _runDefaultScenarioAccToke();

        vm.startPrank(operator);
        rewarder.setTokeLockDuration(30 days);
        vm.stopPrank();

        // mock rewarder balanceOf function
        rewarder.setBalanceOf(1000);

        uint256 balanceBefore = accToke.balanceOf(RANDOM);
        rewarder.exposed_getRewardWrapper(RANDOM);
        uint256 balanceAfter = accToke.balanceOf(RANDOM);

        assertTrue(balanceAfter > balanceBefore);
    }

    function test_AccToke_Staking_Should_Not_Happen_If_No_Lock_Duration() public {
        AccToke accToke = _setupAccTokeAndTokeRewarder();
        _runDefaultScenarioAccToke();

        assertEq(0, rewarder.tokeLockDuration());

        // mock rewarder balanceOf function
        rewarder.setBalanceOf(1000);

        uint256 balanceBefore = accToke.balanceOf(RANDOM);
        rewarder.exposed_getRewardWrapper(RANDOM);
        uint256 balanceAfter = accToke.balanceOf(RANDOM);

        assertTrue(balanceAfter == balanceBefore);
    }

    // This one covers Sherlock 217-M:
    // https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/217-M/565-best.md
    function test_AccToke_Staking_Should_Not_Happen_If_Amount_Is_Low() public {
        AccToke accToke = _setupAccTokeAndTokeRewarder();
        _runDefaultScenarioAccToke();

        vm.startPrank(operator);
        rewarder.setTokeLockDuration(30 days);
        vm.stopPrank();

        // mock rewarder balanceOf function
        rewarder.setBalanceOf(1);
        // and assert that earned is less than tokeMinStakeAmount
        assertTrue(rewarder.earned(RANDOM) < tokeMinStakeAmount);

        uint256 balanceBefore = accToke.balanceOf(RANDOM);
        rewarder.exposed_getRewardWrapper(RANDOM);
        uint256 balanceAfter = accToke.balanceOf(RANDOM);

        assertTrue(balanceAfter == balanceBefore);
    }
}
