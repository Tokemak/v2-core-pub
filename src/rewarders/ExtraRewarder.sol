// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";
import { IExtraRewarder } from "src/interfaces/rewarders/IExtraRewarder.sol";
import { AbstractRewarder } from "./AbstractRewarder.sol";

import { Errors } from "src/utils/Errors.sol";

contract ExtraRewarder is AbstractRewarder, IExtraRewarder, ReentrancyGuard {
    address public immutable mainReward;

    error MainRewardOnly();

    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        address _mainReward,
        uint256 _newRewardRatio,
        uint256 _durationInBlock
    ) AbstractRewarder(_systemRegistry, _stakeTracker, _rewardToken, _newRewardRatio, _durationInBlock) {
        Errors.verifyNotZero(_mainReward, "_mainReward");

        // slither-disable-next-line missing-zero-check
        mainReward = _mainReward;
    }

    modifier mainRewardOnly() {
        if (msg.sender != mainReward) {
            revert MainRewardOnly();
        }
        _;
    }

    function stake(address account, uint256 amount) external mainRewardOnly {
        _updateReward(account);
        _stake(account, amount);
    }

    function withdraw(address account, uint256 amount) external mainRewardOnly {
        _updateReward(account);
        _withdraw(account, amount);
    }

    function getReward(address account) public nonReentrant {
        if (msg.sender != mainReward && msg.sender != account) {
            revert Errors.AccessDenied();
        }
        _updateReward(account);
        _getReward(account);
    }

    function getReward() external {
        getReward(msg.sender);
    }
}
