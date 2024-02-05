// solhint-disable not-rely-on-time
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { ERC20Votes } from "openzeppelin-contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { Pausable } from "openzeppelin-contracts/security/Pausable.sol";
import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";

import { PRBMathUD60x18 } from "prb-math/contracts/PRBMathUD60x18.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { IAccToke } from "src/interfaces/staking/IAccToke.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract AccToke is IAccToke, ERC20Votes, Pausable, SystemComponent, SecurityBase {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IWETH9;

    // variables
    uint256 public immutable startEpoch;
    uint256 public immutable minStakeDuration;
    // solhint-disable-next-line const-name-snakecase
    uint256 public maxStakeDuration = 1461 days; // default 4 years
    uint256 public constant MIN_STAKE_AMOUNT = 10_000;
    uint256 public constant MAX_STAKE_AMOUNT = 100e6 * 1e18; // default 100m toke

    mapping(address => Lockup[]) public lockups;

    uint256 private constant YEAR_BASE_BOOST = 18e17;
    IERC20Metadata public immutable toke;

    //
    // Reward Vars
    //
    IWETH9 private immutable weth;

    uint256 public constant REWARD_FACTOR = 1e12;

    // tracks user's checkpointed reward debt per share
    mapping(address => uint256) public rewardDebtPerShare;
    // keeps track of rewards checkpointed / offloaded but not yet transferred
    mapping(address => uint256) private unclaimedRewards;
    // total current accumulated reward per share
    uint256 public accRewardPerShare;

    // See {IAccToke-totalRewardsEarned}
    uint256 public totalRewardsEarned;
    // See {IAccToke-totalRewardsClaimed}
    uint256 public totalRewardsClaimed;
    // See {IAccToke-rewardsClaimed}
    mapping(address => uint256) public rewardsClaimed;

    constructor(
        ISystemRegistry _systemRegistry,
        uint256 _startEpoch,
        uint256 _minStakeDuration
    )
        SystemComponent(_systemRegistry)
        ERC20("Staked Toke", "accToke")
        ERC20Permit("accToke")
        SecurityBase(address(_systemRegistry.accessController()))
    {
        startEpoch = _startEpoch;
        minStakeDuration = _minStakeDuration;

        toke = systemRegistry.toke();
        weth = systemRegistry.weth();
    }

    // @dev short-circuit transfers
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    // @dev short-circuit transfers
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    /// @inheritdoc IAccToke
    function stake(uint256 amount, uint256 duration, address to) external {
        _stake(amount, duration, to);
    }

    /// @inheritdoc IAccToke
    function stake(uint256 amount, uint256 duration) external {
        _stake(amount, duration, msg.sender);
    }

    /// @inheritdoc IAccToke
    function isStakeableAmount(uint256 amount) public pure returns (bool) {
        return amount >= MIN_STAKE_AMOUNT && amount <= MAX_STAKE_AMOUNT;
    }

    function _stake(uint256 amount, uint256 duration, address to) internal whenNotPaused {
        //
        // validation checks
        //
        if (to == address(0)) revert ZeroAddress();
        if (!isStakeableAmount(amount)) revert IncorrectStakingAmount();

        // duration checked inside previewPoints
        (uint256 points, uint256 end) = previewPoints(amount, duration);

        if (points + totalSupply() > type(uint192).max) {
            revert StakingPointsExceeded();
        }

        // checkpoint rewards for caller
        _collectRewards(to, false);

        // save information for current lockup
        lockups[to].push(Lockup({ amount: SafeCast.toUint128(amount), end: SafeCast.toUint128(end), points: points }));

        // create points for user
        _mint(to, points);

        emit Stake(to, lockups[to].length - 1, amount, end, points);

        // transfer staked toke in
        toke.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IAccToke
    function unstake(uint256[] memory lockupIds) external whenNotPaused {
        _collectRewards(msg.sender, false);

        uint256 length = lockupIds.length;
        if (length == 0) revert InvalidLockupIds();

        uint256 totalPoints = 0;
        uint256 totalAmount = 0;

        uint256 totalLockups = lockups[msg.sender].length;
        for (uint256 iter = 0; iter < length;) {
            uint256 lockupId = lockupIds[iter];
            if (lockupId >= totalLockups) revert LockupDoesNotExist();

            // get staking information
            Lockup memory lockup = lockups[msg.sender][lockupId];

            // slither-disable-next-line timestamp
            if (block.timestamp < lockup.end) revert NotUnlockableYet();
            if (lockup.end == 0) revert AlreadyUnlocked();

            // remove stake
            delete lockups[msg.sender][lockupId];

            // tally total points to be burned
            totalPoints += lockup.points;

            emit Unstake(msg.sender, lockupId, lockup.amount, lockup.end, lockup.points);

            // tally total toke amount to be returned
            totalAmount += lockup.amount;

            unchecked {
                ++iter;
            }
        }

        // wipe points
        _burn(msg.sender, totalPoints);
        // send staked toke back to user
        toke.safeTransfer(msg.sender, totalAmount);
    }

    /// @inheritdoc IAccToke
    function extend(uint256[] memory lockupIds, uint256[] memory durations) external whenNotPaused {
        uint256 length = lockupIds.length;
        if (length == 0) revert InvalidLockupIds();
        if (length != durations.length) revert InvalidDurationLength();

        // before doing anything, make sure the rewards checkpoints are updated!
        _collectRewards(msg.sender, false);

        uint256 totalExtendedPoints = 0;

        uint256 totalLockups = lockups[msg.sender].length;
        for (uint256 iter = 0; iter < length;) {
            uint256 lockupId = lockupIds[iter];
            uint256 duration = durations[iter];
            if (lockupId >= totalLockups) revert LockupDoesNotExist();

            // duration checked inside previewPoints
            Lockup storage lockup = lockups[msg.sender][lockupId];
            uint256 oldAmount = lockup.amount;
            uint256 oldEnd = lockup.end;
            uint256 oldPoints = lockup.points;

            (uint256 newPoints, uint256 newEnd) = previewPoints(oldAmount, duration);

            if (newEnd <= oldEnd) revert ExtendDurationTooShort();
            lockup.end = SafeCast.toUint128(newEnd);
            lockup.points = newPoints;
            totalExtendedPoints = totalExtendedPoints + newPoints - oldPoints;

            emit Extend(msg.sender, lockupId, oldAmount, oldEnd, newEnd, oldPoints, newPoints);

            unchecked {
                ++iter;
            }
        }

        // issue extra points for extension
        _mint(msg.sender, totalExtendedPoints);
    }

    /// @inheritdoc IAccToke
    function previewPoints(uint256 amount, uint256 duration) public view returns (uint256 points, uint256 end) {
        if (duration < minStakeDuration) revert StakingDurationTooShort();
        if (duration > maxStakeDuration) revert StakingDurationTooLong();

        // slither-disable-next-line timestamp
        uint256 start = block.timestamp > startEpoch ? block.timestamp : startEpoch;
        end = start + duration;

        // calculate points based on duration from staking end date
        uint256 endYearpoc = ((end - startEpoch) * 1e18) / 365 days;
        uint256 multiplier = PRBMathUD60x18.pow(YEAR_BASE_BOOST, endYearpoc);

        points = (amount * multiplier) / 1e18;
    }

    /// @inheritdoc IAccToke
    function getLockups(address user) external view returns (Lockup[] memory) {
        return lockups[user];
    }

    /// @notice Update max stake duration allowed
    function setMaxStakeDuration(uint256 _maxStakeDuration) external onlyOwner {
        uint256 old = maxStakeDuration;

        maxStakeDuration = _maxStakeDuration;

        emit SetMaxStakeDuration(old, _maxStakeDuration);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* **************************************************************************** */
    /*																				*/
    /* 									Rewards										*/
    /*																				*/
    /* **************************************************************************** */

    /// @notice Allows an actor to deposit ETH as staking reward to be distributed to all staked participants
    /// @param amount Amount of `WETH` to take from caller and deposit as reward for the stakers
    function addWETHRewards(uint256 amount) external {
        // update accounting to factor in new rewards
        _addWETHRewards(amount);
        // actually transfer WETH
        weth.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Internal function used by both `addWETHRewards` external and the `receive()` function
    /// @param amount See {IAccToke-addWETHRewards}.
    function _addWETHRewards(uint256 amount) internal whenNotPaused {
        Errors.verifyNotZero(amount, "amount");

        uint256 supply = totalSupply();
        Errors.verifyNotZero(supply, "supply");

        if (amount * REWARD_FACTOR < supply) {
            revert InsufficientAmount();
        }

        totalRewardsEarned += amount;
        accRewardPerShare += amount * REWARD_FACTOR / supply;

        emit RewardsAdded(amount, accRewardPerShare);
    }

    /// @inheritdoc IAccToke
    function previewRewards() external view returns (uint256 amount) {
        return previewRewards(msg.sender);
    }

    /// @inheritdoc IAccToke
    function previewRewards(address user) public view returns (uint256 amount) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return unclaimedRewards[user];
        }

        // calculate reward per share by taking the current reward per share and subtracting what user already claimed
        uint256 _netRewardsPerShare = accRewardPerShare - rewardDebtPerShare[user];

        // calculate full reward user is entitled to by taking their recently earned and adding unclaimed checkpointed
        return ((balanceOf(user) * _netRewardsPerShare) / REWARD_FACTOR) + unclaimedRewards[user];
    }

    /// @inheritdoc IAccToke
    function collectRewards() external returns (uint256) {
        return _collectRewards(msg.sender, true);
    }

    /// @dev See {IAccToke-collectRewards}.
    function _collectRewards(address user, bool distribute) internal returns (uint256) {
        // calculate user's new rewards per share (current minus claimed)
        uint256 netRewardsPerShare = accRewardPerShare - rewardDebtPerShare[user];
        // calculate amount of actual rewards
        uint256 netRewards = (balanceOf(user) * netRewardsPerShare) / REWARD_FACTOR;
        // get reference to user's pending (sandboxed) rewards
        uint256 pendingRewards = unclaimedRewards[user];

        // update checkpoint to current
        rewardDebtPerShare[user] = accRewardPerShare;

        // if nothing to claim, bail
        if (netRewards == 0 && pendingRewards == 0) {
            return 0;
        }

        if (distribute) {
            //
            // if asked for actual distribution, transfer all earnings
            //

            // reset sandboxed rewards
            unclaimedRewards[user] = 0;

            // get total amount by adding new rewards and previously sandboxed
            uint256 totalClaiming = netRewards + pendingRewards;

            // update running totals
            //slither-disable-next-line costly-loop
            totalRewardsClaimed += totalClaiming;
            rewardsClaimed[user] += totalClaiming;

            emit RewardsClaimed(user, totalClaiming);

            // send rewards to user
            weth.safeTransfer(user, totalClaiming);

            // return total amount claimed
            return totalClaiming;
        }

        if (netRewards > 0) {
            // Save (sandbox) to their account for later transfer
            unclaimedRewards[user] += netRewards;

            emit RewardsCollected(user, netRewards);
        }

        // nothing collected
        return 0;
    }

    /// @notice Catch-all. If any eth is sent, wrap and add to rewards
    receive() external payable {
        // update accounting to factor in new rewards
        // NOTE: doing it in this order keeps slither happy
        _addWETHRewards(msg.value);
        // appreciate the ETH! wrap and add as rewards
        weth.deposit{ value: msg.value }();
    }
}
