// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { MainRewarder, ISystemRegistry, Errors } from "src/rewarders/MainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";

/**
 * @title LMPVaultMainRewarder
 * @notice Main rewarder for LMP Vault contracts.  This is used to enforce role based
 *      access control for LMP rewarders.
 */
contract LMPVaultMainRewarder is MainRewarder {
    using SafeERC20 for IERC20;

    /// @notice IERC20 instance of token being staked in rewarder.
    IERC20 public immutable stakingToken;

    // slither-disable-start similar-names
    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraReward,
        address _stakingToken
    )
        MainRewarder(
            _systemRegistry,
            _rewardToken,
            _newRewardRatio,
            _durationInBlock,
            Roles.LMP_REWARD_MANAGER_ROLE,
            _allowExtraReward
        )
    {
        Errors.verifyNotZero(_stakingToken, "_stakingToken");

        stakingToken = IERC20(_stakingToken);
    }
    // slither-disable-end similar-names

    /**
     * @notice Withdraws autopilot vault token from rewarder.
     * @dev Balance updates, reward calculations taken care of in inherited contract.
     * @param account Account that is withdrawing assets.
     * @param amount Amount of assets to be withdrawn.
     * @param claim Whether or not to claim rewards.
     */
    function withdraw(address account, uint256 amount, bool claim) public {
        if (msg.sender != account && msg.sender != address(systemRegistry.lmpVaultRouter())) {
            revert Errors.AccessDenied();
        }

        _withdraw(account, amount, claim);

        stakingToken.safeTransfer(account, amount);
    }

    /**
     * @notice Stakes autopilot vault token to rewarder.
     * @dev Balance updates, reward calculations taken care of in inherited contract.
     * @param account Account staking.
     * @param amount Amount of autopilot vault token to stake.
     */
    function stake(address account, uint256 amount) public {
        _stake(account, amount);

        // slither-disable-next-line arbitrary-send-erc20
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Gets reward for msg.sender.
     * @dev Used to enforce msg.sender check.
     * @param account Account to claim rewards for
     */
    function getReward(address account, bool claimExtras) public {
        if (msg.sender != account && msg.sender != address(systemRegistry.lmpVaultRouter())) {
            revert Errors.AccessDenied();
        }

        _getReward(account, claimExtras);
    }
}
