// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.17;

interface IBasePool {
    /// @notice Returns the pool ID
    function getPoolId() external view returns (bytes32);

    /// @notice Returns the current swap fee percentage as a 18 decimal fixed point number
    /// @return The current swap fee percentage
    function getSwapFeePercentage() external view returns (uint256);
}
