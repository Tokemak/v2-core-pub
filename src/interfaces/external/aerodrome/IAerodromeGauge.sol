// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IAerodromeGauge is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function getReward(address account) external;
}
