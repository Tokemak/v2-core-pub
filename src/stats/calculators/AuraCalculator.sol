// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AuraRewards } from "src/libs/AuraRewards.sol";
import { IAuraStashToken } from "src/interfaces/external/aura/IAuraStashToken.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
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

    /// @dev For the Aura implementation every `rewardToken()` is a stash token
    function resolveRewardToken(address extraRewarder) public view override returns (address rewardToken) {
        IERC20 rewardTokenErc = IBaseRewardPool(extraRewarder).rewardToken();
        IAuraStashToken stashToken = IAuraStashToken(address(rewardTokenErc));
        if (stashToken.isValid()) {
            rewardToken = stashToken.baseToken();
        }
    }
}
