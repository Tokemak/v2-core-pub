// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { AuraRewards } from "src/libs/AuraRewards.sol";
import { IBooster } from "src/interfaces/external/aura/IBooster.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IAuraStashToken } from "src/interfaces/external/aura/IAuraStashToken.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract AuraCalculator is IncentiveCalculatorBase {
    address public immutable BOOSTER;
    address public balLpToken;

    constructor(ISystemRegistry _systemRegistry, address _booster) IncentiveCalculatorBase(_systemRegistry) {
        Errors.verifyNotZero(_booster, "_booster");

        // slither-disable-next-line missing-zero-check
        BOOSTER = _booster;
    }

    /// @dev initializer protection is on the base class
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) public virtual override {
        super.initialize(dependentAprIds, initData);

        IBooster.PoolInfo memory poolInfo = IBooster(BOOSTER).poolInfo(rewarder.pid());
        Errors.verifyNotZero(poolInfo.lptoken, "lptoken");

        balLpToken = poolInfo.lptoken;
    }

    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view override returns (uint256) {
        return AuraRewards.getAURAMintAmount(_platformToken, BOOSTER, address(rewarder), _annualizedReward);
    }

    /// @dev For the Aura implementation every `rewardToken()` is a stash token
    function resolveRewardToken(address extraRewarder) public view override returns (address rewardToken) {
        IERC20 rewardTokenErc = IBaseRewardPool(extraRewarder).rewardToken();
        IAuraStashToken stashToken = IAuraStashToken(address(rewardTokenErc));
        if (stashToken.isValid()) {
            rewardToken = stashToken.baseToken();
        }
    }

    /// @inheritdoc IncentiveCalculatorBase
    function resolveLpToken() public view virtual override returns (address lpToken) {
        lpToken = balLpToken;
    }
}
