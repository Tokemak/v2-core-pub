// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { MainRewarder, ISystemRegistry } from "src/rewarders/MainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";

/**
 * @title DestinationVaultMainRewarder
 * @notice Main rewarder for Destination Vault contracts.  This is used to enforce role based
 *      access control for Destination Vault rewarders.
 */
contract DestinationVaultMainRewarder is MainRewarder {
    // slither-disable-start similar-names
    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraReward
    )
        MainRewarder(
            _systemRegistry,
            _stakeTracker,
            _rewardToken,
            _newRewardRatio,
            _durationInBlock,
            Roles.DV_REWARD_MANAGER_ROLE,
            _allowExtraReward
        )
    { }
    // slither-disable-end
}
