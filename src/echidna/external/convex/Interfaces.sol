// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/* solhint-disable max-line-length */

// adapted from:
// https://github.com/convex-eth/platform/blob/ad8f90a4df441c789d1f4163c5d99f7ccd67fd4e/contracts/contracts/Interfaces.sol

interface IRewards {
    function stake(address, uint256) external;
    function stakeFor(address, uint256) external;
    function withdraw(address, uint256) external;
    function exit(address) external;
    function getReward(address) external;
    function queueNewRewards(uint256) external;
    function notifyRewardAmount(uint256) external;
    function addExtraReward(address) external;
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function earned(address account) external view returns (uint256);
}

interface IDeposit {
    function isShutdown() external view returns (bool);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function poolInfo(uint256) external view returns (address, address, address, address, address, bool);
    function rewardClaimed(uint256, address, uint256) external;
    function withdrawTo(uint256, uint256, address) external;
    function claimRewards(uint256, address) external returns (bool);
    function rewardArbitrator() external returns (address);
    function setGaugeRedirect(uint256 _pid) external returns (bool);
    function owner() external returns (address);
}
