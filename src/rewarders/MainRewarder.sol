// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IExtraRewarder } from "src/interfaces/rewarders/IExtraRewarder.sol";
import { AbstractRewarder } from "src/rewarders/AbstractRewarder.sol";

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title MainRewarder
 * @notice The MainRewarder contract extends the AbstractRewarder and
 * manages the distribution of main rewards along with additional rewards
 * from ExtraRewarder contracts.
 */
contract MainRewarder is AbstractRewarder, IMainRewarder, ReentrancyGuard {
    /// @notice True if additional reward tokens/contracts are allowed to be added
    /// @dev Destination Vaults should not allow extras. LMP should.
    bool public immutable allowExtraRewards;

    /// @notice An instance of the stake tracking contract
    address public immutable stakeTracker;

    address[] public extraRewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    error ExtraRewardsNotAllowed();

    event ExtraRewardAdded(address reward);
    event ExtraRewardsCleared();

    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraRewards
    ) AbstractRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock) {
        Errors.verifyNotZero(_stakeTracker, "_stakeTracker");

        // slither-disable-next-line missing-zero-check
        stakeTracker = _stakeTracker;
        allowExtraRewards = _allowExtraRewards;
    }

    /// @notice Restricts access to the stake tracker only.
    modifier onlyStakeTracker() {
        if (msg.sender != stakeTracker) {
            revert Errors.AccessDenied();
        }
        _;
    }

    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    function addExtraReward(address reward) external hasRole(Roles.DV_REWARD_MANAGER_ROLE) {
        if (!allowExtraRewards) {
            revert ExtraRewardsNotAllowed();
        }
        Errors.verifyNotZero(reward, "reward");

        extraRewards.push(reward);

        emit ExtraRewardAdded(reward);
    }

    function getExtraRewarder(uint256 index) external view returns (IExtraRewarder rewarder) {
        return IExtraRewarder(extraRewards[index]);
    }

    function clearExtraRewards() external hasRole(Roles.DV_REWARD_MANAGER_ROLE) {
        delete extraRewards;

        emit ExtraRewardsCleared();
    }

    function withdraw(address account, uint256 amount, bool claim) public onlyStakeTracker {
        _updateReward(account);
        _withdraw(account, amount);

        for (uint256 i = 0; i < extraRewards.length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(extraRewards[i]).withdraw(account, amount);
        }

        if (claim) {
            _processRewards(account, true);
        }

        // slither-disable-next-line events-maths
        _totalSupply -= amount;
        _balances[account] -= amount;
    }

    function stake(address account, uint256 amount) public onlyStakeTracker {
        _updateReward(account);
        _stake(account, amount);

        for (uint256 i = 0; i < extraRewards.length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(extraRewards[i]).stake(account, amount);
        }

        // slither-disable-next-line events-maths
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function getReward() external nonReentrant {
        _updateReward(msg.sender);
        _processRewards(msg.sender, true);
    }

    function getReward(address account, bool claimExtras) external nonReentrant {
        if (msg.sender != stakeTracker && msg.sender != account) {
            revert Errors.AccessDenied();
        }
        _updateReward(account);
        _processRewards(account, claimExtras);
    }

    function totalSupply() public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return _balances[account];
    }

    function _processRewards(address account, bool claimExtras) internal {
        _getReward(account);

        //also get rewards from linked rewards
        if (claimExtras) {
            for (uint256 i = 0; i < extraRewards.length; ++i) {
                IExtraRewarder(extraRewards[i]).getReward(account);
            }
        }
    }
}
