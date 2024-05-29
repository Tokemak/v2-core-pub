// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IAerodromeGauge is IERC20 {
    // function deposit(uint256 amount, uint256 tokenId) external;
    // function withdraw(uint256 amount) external;
    // function withdrawToken(uint256 amount, uint256 tokenId) external;
    // function stake() external view returns (address);
    function rewardToken() external view returns (address);
    // function rewardsListLength() external view returns (uint256);
    function getReward(address account) external;
    // function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
