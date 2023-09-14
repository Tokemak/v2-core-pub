// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.17;

interface IBasePool {
    /// @notice Returns the pool ID
    function getPoolId() external view returns (bytes32);

    /// @notice Returns true if the Pool is in Recovery Mode
    function inRecoveryMode() external view returns (bool);
}
