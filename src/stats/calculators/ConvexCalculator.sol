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

    function resolveRewardToken(address extraRewarder) public view override returns (address rewardToken) {
        IBaseRewardPool extraRwrdr = IBaseRewardPool(extraRewarder);

        // 151+ PID reference: https://docs.convexfinance.com/convexfinanceintegration/baserewardpool
        // Taking PID from base rewarder contract in IncentiveCalculatorBase:
        uint256 pid = rewarder.pid();
        if (pid >= 151) {
            // If the pool id is >= 151, then it is a stash token. Retrieving the actual token value
            rewardToken = ITokenWrapper(address(extraRwrdr.rewardToken())).token();
        } else {
            // If the pool id is < 151, then taking the reward token
            rewardToken = address(extraRwrdr.rewardToken());
        }
    }
}
