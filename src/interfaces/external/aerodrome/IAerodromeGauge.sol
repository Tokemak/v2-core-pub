// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAerodromeGauge {
    /// @notice Deposit LP tokens into gauge for any user
    /// @param _amount .
    function deposit(uint256 _amount) external;

    /// @notice Withdraw LP tokens for user
    /// @param _amount .
    function withdraw(uint256 _amount) external;

    /// @notice Address of the pool LP token which is deposited (staked) for rewards
    function stakingToken() external view returns (address);

    /// @notice Address of the token (AERO) rewarded to stakers
    function rewardToken() external view returns (address);

    /// @notice Retrieve rewards for an address.
    /// @dev Throws if not called by same address or voter.
    /// @param _account .
    function getReward(address _account) external;

    /// @notice Get the amount of stakingToken deposited by an account
    function balanceOf(address) external view returns (uint256);

    /// @notice Amount of stakingToken deposited for rewards
    function totalSupply() external view returns (uint256);
}
