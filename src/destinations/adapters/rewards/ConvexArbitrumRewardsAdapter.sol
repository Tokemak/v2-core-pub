// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { IConvexRewardPool, RewardType } from "src/interfaces/external/convex/IConvexRewardPool.sol";

library ConvexArbitrumRewardsAdapter {
    /**
     * @notice Gets all rewards from the reward pool on Arbitrum
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param gauge The gauge to claim rewards from
     * @return amountsClaimed Quantity of reward tokens
     * @return rewardTokens Addresses of claimed reward tokens
     */
    function claimRewards(address gauge)
        public
        returns (uint256[] memory amountsClaimed, address[] memory rewardTokens)
    {
        Errors.verifyNotZero(gauge, "gauge");

        address account = address(this);

        IConvexRewardPool rewardPool = IConvexRewardPool(gauge);
        uint256 rewardsLength = rewardPool.rewardLength();

        uint256[] memory balancesBefore = new uint256[](rewardsLength);
        amountsClaimed = new uint256[](rewardsLength);
        rewardTokens = new address[](rewardsLength);

        // get balances before
        for (uint256 i = 0; i < rewardsLength; ++i) {
            RewardType memory rewardType = rewardPool.rewards(i);
            IERC20 token = IERC20(rewardType.reward_token);
            rewardTokens[i] = address(token);
            balancesBefore[i] = token.balanceOf(account);
        }
        // TODO: Check if it mints CVX by default

        // claim rewards
        rewardPool.getReward(account);

        // get balances after and calculate amounts claimed
        for (uint256 i = 0; i < rewardsLength; ++i) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(account);
            amountsClaimed[i] = balance - balancesBefore[i];
        }

        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);
    }
}
