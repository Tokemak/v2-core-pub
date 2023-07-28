// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { IRewardsOnlyGauge } from "src/interfaces/external/beethoven/IRewardsOnlyGauge.sol";
import { IChildChainStreamer } from "src/interfaces/external/beethoven/IChildChainStreamer.sol";
import { IChildChainGaugeRewardHelper } from "src/interfaces/external/beethoven/IChildChainGaugeRewardHelper.sol";

library BeethovenRewardsAdapter {
    /**
     * @notice Claim rewards for Balancer staked LP tokens
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param gauge The gauge to claim rewards from
     * @return amountsClaimed Quantity of reward tokens
     * @return rewardTokens Addresses of claimed reward tokens
     */
    function claimRewards(
        IChildChainGaugeRewardHelper gaugeRewardHelper,
        address gauge
    ) public returns (uint256[] memory amountsClaimed, address[] memory rewardTokens) {
        Errors.verifyNotZero(address(gaugeRewardHelper), "gaugeRewardHelper");
        Errors.verifyNotZero(gauge, "gauge");

        address account = address(this);

        IRewardsOnlyGauge gaugeContract = IRewardsOnlyGauge(gauge);

        IChildChainStreamer streamer = gaugeContract.reward_contract();
        uint256 count = streamer.reward_count();

        uint256[] memory balancesBefore = new uint256[](count);
        rewardTokens = new address[](count);
        amountsClaimed = new uint256[](count);

        // get balances before
        for (uint256 i = 0; i < count; ++i) {
            IERC20 token = streamer.reward_tokens(i);
            rewardTokens[i] = address(token);
            balancesBefore[i] = token.balanceOf(account);
        }

        // claim rewards
        gaugeRewardHelper.claimRewards(gaugeContract, account);

        // get balances after and calculate amounts claimed
        for (uint256 i = 0; i < count; ++i) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(account);

            uint256 claimed = balance - balancesBefore[i];
            amountsClaimed[i] = claimed;
        }
        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);

        return (amountsClaimed, rewardTokens);
    }
}
