// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IAerodromeGauge } from "src/interfaces/external/aerodrome/IAerodromeGauge.sol";

import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title AerodromeRewardsAdapter
 * @dev This contract implements an adapter for interacting with Aerodrome Finance's reward system.
 * The Aerodrome Finance in comparison to Velodrome (where it forked from) offers the only one type of rewards:
 *  - Emissions:  rewards distributed to liquidity providers based on their share of the liquidity pool.
 *      - _claimEmissions() is used to claim these rewards.
 */
library AerodromeRewardsAdapter {
    /**
     * @param voter Aerodrome's Voter contract
     * @param pool The pool to claim rewards from
     * @param claimFor The account to check & claim rewards for (should be a caller)
     */
    function claimRewards(
        IVoter voter,
        address pool,
        address claimFor
    ) public returns (uint256[] memory amountsClaimed, IERC20[] memory rewardTokens) {
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
        IAerodromeGauge gauge = IAerodromeGauge(gaugeAddress);

        uint256[] memory balancesBefore = new uint256[](1);
        amountsClaimed = new uint256[](1);
        rewards = new IERC20[](1);

        address rewardToken = gauge.rewardToken();
        Errors.verifyNotZero(rewardToken, "rewardToken");
        IERC20 rewardErc = IERC20(rewardToken);

        rewards[0] = rewardErc;
        balancesBefore[0] = rewardErc.balanceOf(claimFor);

        gauge.getReward(claimFor);

        uint256 balanceAfter = rewards[0].balanceOf(claimFor);
        amountsClaimed[0] = balanceAfter - balancesBefore[0];
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
