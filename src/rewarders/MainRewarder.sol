// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IExtraRewarder } from "src/interfaces/rewarders/IExtraRewarder.sol";
import { AbstractRewarder } from "src/rewarders/AbstractRewarder.sol";

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title MainRewarder
 * @dev Contract is abstract to enforce proper role designation on construction
 * @notice The MainRewarder contract extends the AbstractRewarder and
 * manages the distribution of main rewards along with additional rewards
 * from ExtraRewarder contracts.
 */
abstract contract MainRewarder is AbstractRewarder, IMainRewarder, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice True if additional reward tokens/contracts are allowed to be added
    /// @dev Destination Vaults should not allow extras. LMP should.
    bool public immutable allowExtraRewards;

    EnumerableSet.AddressSet private _extraRewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bytes32 _rewardRole,
        bool _allowExtraRewards
    ) AbstractRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock, _rewardRole) {
        // slither-disable-next-line missing-zero-check
        allowExtraRewards = _allowExtraRewards;
    }

    function extraRewardsLength() external view returns (uint256) {
        return _extraRewards.length();
    }

    function addExtraReward(address reward) external hasRole(rewardRole) {
        if (!allowExtraRewards) {
            revert ExtraRewardsNotAllowed();
        }
        Errors.verifyNotZero(reward, "reward");

        if (!_extraRewards.add(reward)) {
            revert Errors.ItemExists();
        }

        emit ExtraRewardAdded(reward);
    }

    function getExtraRewarder(uint256 index) external view returns (IExtraRewarder rewarder) {
        return IExtraRewarder(_extraRewards.at(index));
    }

    function removeExtraRewards(address[] calldata _rewards) external hasRole(rewardRole) {
        uint256 length = _rewards.length;
        for (uint256 i = 0; i < length; ++i) {
            if (!_extraRewards.remove(_rewards[i])) {
                revert Errors.ItemNotFound();
            }
            emit ExtraRewardRemoved(_rewards[i]);
        }
    }

    function clearExtraRewards() external hasRole(rewardRole) {
        while (_extraRewards.length() > 0) {
            if (!_extraRewards.remove(_extraRewards.at(_extraRewards.length() - 1))) {
                revert Errors.ItemNotFound();
            }
        }

        emit ExtraRewardsCleared();
    }

    function extraRewards() external view returns (address[] memory) {
        return _extraRewards.values();
    }

    function _withdraw(address account, uint256 amount, bool claim) internal {
        _updateReward(account);
        _withdrawAbstractRewarder(account, amount);

        uint256 length = _extraRewards.length();
        for (uint256 i = 0; i < length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(_extraRewards.at(i)).withdraw(account, amount);
        }

        if (claim) {
            _processRewards(account, true);
        }

        // slither-disable-next-line events-maths
        _totalSupply -= amount;
        _balances[account] -= amount;
    }

    function _stake(address account, uint256 amount) internal {
        _updateReward(account);
        _stakeAbstractRewarder(account, amount);

        uint256 length = _extraRewards.length();
        for (uint256 i = 0; i < length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(_extraRewards.at(i)).stake(account, amount);
        }

        // slither-disable-next-line events-maths
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function getReward() external nonReentrant {
        _updateReward(msg.sender);
        _processRewards(msg.sender, true);
    }

    function _getReward(address account, bool claimExtras) internal nonReentrant {
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
        uint256 length = _extraRewards.length();

        //also get rewards from linked rewards
        if (claimExtras) {
            for (uint256 i = 0; i < length; ++i) {
                IExtraRewarder(_extraRewards.at(i)).getReward(account);
            }
        }
    }
}
