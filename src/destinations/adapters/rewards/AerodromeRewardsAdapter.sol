// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IGauge } from "src/interfaces/external/velodrome/IGauge.sol";

import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title AerodromeRewardsAdapter
 * @dev This contract implements an adapter for interacting with Aerodrome Finance's reward system.
 * The Aerodrome Finance platform offers four types of rewards:
 *  - Emissions:  rewards distributed to liquidity providers based on their share of the liquidity pool.
 *      - _claimEmissions() is used to claim these rewards.
 *  - Fees: rewards distributed to users who interact with the platform through trades or other actions.
 *      - _claimFees() is used to claim these rewards.
 *
 */
library AerodromeRewardsAdapter {
    /**
     * @param voter Aerodrome's Voter contract
     *
     * @param pool The pool to claim rewards from
     * @param claimFor The account to check & claim rewards for (should be a caller)
     */
    function claimRewards(
        IVoter voter,
        address pool,
        address claimFor
    ) internal returns (uint256[] memory amountsClaimed, IERC20[] memory rewardTokens) {
        Errors.verifyNotZero(address(voter), "voter");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(claimFor, "claimFor");

        address gaugeAddress = voter.gauges(pool);

        (amountsClaimed, rewardTokens) = _claimEmissions(gaugeAddress, claimFor);

        RewardAdapter.emitRewardsClaimed(_convertToAddresses(rewardTokens), amountsClaimed);
    }

    function _claimEmissions(
        address gaugeAddress,
        address claimFor
    ) private returns (uint256[] memory amountsClaimed, IERC20[] memory rewards) {
        IGauge gauge = IGauge(gaugeAddress);
        address[] memory gaugeRewards = _getGaugeRewards(gauge);

        uint256 count = gaugeRewards.length;
        uint256[] memory balancesBefore = new uint256[](count);
        amountsClaimed = new uint256[](count);
        rewards = new IERC20[](count);

        for (uint256 i = 0; i < count; ++i) {
            IERC20 reward = IERC20(gaugeRewards[i]);
            rewards[i] = reward;
            balancesBefore[i] = reward.balanceOf(claimFor);
        }

        gauge.getReward(claimFor, gaugeRewards);

        for (uint256 i = 0; i < count; ++i) {
            uint256 balanceAfter = rewards[i].balanceOf(claimFor);
            amountsClaimed[i] = balanceAfter - balancesBefore[i];
        }
    }

    function _getGaugeRewards(IGauge gauge) private view returns (address[] memory rewards) {
        uint256 length = gauge.rewardsListLength();

        rewards = new address[](length);

        for (uint256 i = 0; i < length; ++i) {
            address reward = gauge.rewards(i);
            rewards[i] = reward;
        }
    }

    function _convertToAddresses(IERC20[] memory tokens) internal pure returns (address[] memory assets) {
        //slither-disable-start assembly
        //solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
        //slither-disable-end assembly
    }
}
