// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";

//slither-disable-next-line missing-inheritance
library ConvexRewards {
    using Address for address;
    using SafeERC20 for IERC20;

    /// @notice Claim rewards for Convex staked LP tokens
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @param sendTo the destination of the rewarded tokens
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function claimRewards(
        address gauge,
        address defaultToken,
        address sendTo
    ) public returns (uint256[] memory amounts, address[] memory tokens) {
        return _claimRewards(gauge, defaultToken, sendTo);
    }

    /// @notice Claim rewards for Convex staked LP tokens
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function claimRewards(
        address gauge,
        address defaultToken
    ) public returns (uint256[] memory amounts, address[] memory tokens) {
        return _claimRewards(gauge, defaultToken, address(this));
    }

    /// @notice Claim rewards for Convex staked LP tokens
    /// @dev tokens are ordered as: extras, crv/bal, default (cvx/aura)
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @param sendTo the destination of the rewarded tokens
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function _claimRewards(
        address gauge,
        address defaultToken,
        address sendTo
    ) internal returns (uint256[] memory amounts, address[] memory tokens) {
        Errors.verifyNotZero(gauge, "gauge");

        address account = address(this);

        IBaseRewardPool rewardPool = IBaseRewardPool(gauge);
        uint256 extraRewardsLength = rewardPool.extraRewardsLength();
        uint256 totalLength = extraRewardsLength + (defaultToken != address(0) ? 2 : 1);

        uint256[] memory balancesBefore = new uint256[](totalLength);
        uint256[] memory amountsClaimed = new uint256[](totalLength);
        address[] memory rewardTokens = new address[](totalLength);

        // add pool rewards tokens and extra rewards tokens to rewardTokens array
        IERC20 rewardToken = rewardPool.rewardToken();
        rewardTokens[extraRewardsLength] = address(rewardToken);
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength; ++i) {
                address extraReward = rewardPool.extraRewards(i);
                rewardTokens[i] = address(IBaseRewardPool(extraReward).rewardToken());
            }
        }
        if (defaultToken != address(0)) {
            rewardTokens[totalLength - 1] = defaultToken;
        }

        // get balances before
        for (uint256 i = 0; i < totalLength; ++i) {
            (bool success, uint256 bal) = _hasBalance(rewardTokens[i], account);
            if (success) {
                balancesBefore[i] = bal;
            }
        }

        // claim rewards
        if (!rewardPool.getReward(account, true)) {
            revert RewardAdapter.ClaimRewardsFailed();
        }

        // get balances after and calculate amounts claimed
        for (uint256 i = 0; i < totalLength; ++i) {
            uint256 balance = 0;
            // Same check for "stash tokens"
            (bool success2, uint256 bal2) = _hasBalance(rewardTokens[i], account);
            if (success2) {
                balance = bal2;
            }

            amountsClaimed[i] = balance - balancesBefore[i];

            if (sendTo != address(this) && amountsClaimed[i] > 0) {
                IERC20(rewardTokens[i]).safeTransfer(sendTo, amountsClaimed[i]);
            }
        }

        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);

        return (amountsClaimed, rewardTokens);
    }

    ///@dev Sometimes addresses stand in as the rewardToken but they don't have a `balanceOf()`, so we verify
    function _hasBalance(address token, address account) private returns (bool hasBalance, uint256 bal) {
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory returnData) = token.call(abi.encodeWithSignature("balanceOf(address)", account));
        if (success && returnData.length > 0) {
            bal = abi.decode(returnData, (uint256));
        }
        hasBalance = success;
    }
}
