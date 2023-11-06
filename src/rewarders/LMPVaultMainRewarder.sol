// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { MainRewarder, ISystemRegistry } from "src/rewarders/MainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";

/**
 * @title LMPVaultMainRewarder
 * @notice Main rewarder for LMP Vault contracts.  This is used to enforce role based
 *      access control between rewarders used in LMP and Destination vaults.
 */
contract LMPVaultMainRewarder is MainRewarder {
    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraReward
    )
        MainRewarder(_systemRegistry, _stakeTracker, _rewardToken, _newRewardRatio, _durationInBlock, _allowExtraReward)
    {
        rewardRole = Roles.LMP_REWARD_MANAGER_ROLE;
    }
}
