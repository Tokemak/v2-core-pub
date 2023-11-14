// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AuraRewards } from "src/libs/AuraRewards.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract AuraCalculator is IncentiveCalculatorBase {
    address public immutable booster;

    constructor(ISystemRegistry _systemRegistry, address _booster) IncentiveCalculatorBase(_systemRegistry) {
        // slither-disable-next-line missing-zero-check
        booster = _booster;
    }

    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view override returns (uint256) {
        return AuraRewards.getAURAMintAmount(_platformToken, booster, address(rewarder), _annualizedReward);
    }

    function resolveRewardToken(
        address baseRewarder,
        address extraRewarder
    ) public pure override returns (address rewardToken) {
        // For the Aura implementation every rewardToken() is a stash token
        // rewardToken = extraRewarder.rewardToken().baseToken();


        // extraRewarder = address(IBaseRewardPool(rewardPool.extraRewards(i));
        IAuraStashToken stashToken = IAuraStashToken().rewardToken();
        if (stashToken.isValid()) {
            rewardToken = stashToken.baseToken();
        }
    }
}
