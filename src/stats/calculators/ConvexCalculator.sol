// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { ConvexRewards } from "src/libs/ConvexRewards.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ITokenWrapper } from "src/interfaces/external/convex/ITokenWrapper.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract ConvexCalculator is IncentiveCalculatorBase {
    address public immutable BOOSTER;
    address public convexLpToken;

    constructor(ISystemRegistry _systemRegistry, address _booster) IncentiveCalculatorBase(_systemRegistry) {
        Errors.verifyNotZero(_booster, "_booster");

        // slither-disable-next-line missing-zero-check
        BOOSTER = _booster;
    }

    /// @dev initializer protection is on the base class
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) public virtual override {
        super.initialize(dependentAprIds, initData);

        // slither-disable-next-line unused-return
        (address lptoken,,,,,) = IConvexBooster(BOOSTER).poolInfo(rewarder.pid());
        Errors.verifyNotZero(lptoken, "lptoken");

        convexLpToken = lptoken;
    }

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

    /// @inheritdoc IncentiveCalculatorBase
    function resolveLpToken() public view virtual override returns (address lpToken) {
        lpToken = convexLpToken;
    }
}
