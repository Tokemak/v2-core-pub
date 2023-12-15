// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ConvexRewards } from "src/libs/ConvexRewards.sol";
import { ITokenWrapper } from "src/interfaces/external/convex/ITokenWrapper.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract ConvexCalculator is IncentiveCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) IncentiveCalculatorBase(_systemRegistry) { }

    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view override returns (uint256) {
        return ConvexRewards.getCVXMintAmount(_platformToken, _annualizedReward);
    }

    /// @notice If the pool id is >= 151, then it is a stash token that should be unwrapped:
    /// Ref: https://docs.convexfinance.com/convexfinanceintegration/baserewardpool
    function resolveRewardToken(address extraRewarder) public view override returns (address rewardToken) {
        rewardToken = address(IBaseRewardPool(extraRewarder).rewardToken());

        // Taking PID from base rewarder
        if (rewarder.pid() >= 151) {
            ITokenWrapper reward = ITokenWrapper(rewardToken);
            // Retrieving the actual token value if token is valid
            rewardToken = reward.isInvalid() ? address(0) : reward.token();
        }
    }
}
