// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// solhint-disable func-name-mixedcase
interface IBooster {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    // @notice index(pid) -> pool
    function poolInfo(uint256 index) external view returns (PoolInfo memory);
    // @notice Reward multiplier for increasing or decreasing AURA rewards per PID
    function REWARD_MULTIPLIER_DENOMINATOR() external view returns (uint256);
    // @notice rewardContract => rewardMultiplier (10000 = 100%)
    function getRewardMultipliers(address rewarder) external view returns (uint256);
}
