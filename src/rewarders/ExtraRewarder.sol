// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IExtraRewarder } from "src/interfaces/rewarders/IExtraRewarder.sol";
import { AbstractRewarder } from "./AbstractRewarder.sol";

import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

contract ExtraRewarder is AbstractRewarder, IExtraRewarder, ReentrancyGuard {
    IMainRewarder public immutable mainReward;

    error MainRewardOnly();

    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        address _mainReward,
        uint256 _newRewardRatio,
        uint256 _durationInBlock
    )
        // solhint-disable-next-line max-line-length
        AbstractRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock, Roles.EXTRA_REWARD_MANAGER_ROLE)
    {
        Errors.verifyNotZero(_mainReward, "_mainReward");

        // slither-disable-next-line missing-zero-check
        mainReward = IMainRewarder(_mainReward);
    }

    modifier mainRewardOnly() {
        if (msg.sender != address(mainReward)) {
            revert MainRewardOnly();
        }
        _;
    }

    function stake(address account, uint256 amount) external mainRewardOnly {
        _updateReward(account);
        _stakeAbstractRewarder(account, amount);
    }

    function withdraw(address account, uint256 amount) external mainRewardOnly {
        _updateReward(account);
        _withdrawAbstractRewarder(account, amount);
    }

    function getReward(address account) public nonReentrant {
        if (msg.sender != address(mainReward) && msg.sender != account) {
            revert Errors.AccessDenied();
        }
        _updateReward(account);
        _getReward(account);
    }

    function getReward() external {
        getReward(msg.sender);
    }

    function totalSupply() public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return mainReward.totalSupply();
    }

    function balanceOf(address account) public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return mainReward.balanceOf(account);
    }
}
