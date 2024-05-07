// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBalancerGyroPool {
    /// @notice Virtual Price equivalent for Gyro Pools
    function getInvariantDivActualSupply() external view returns (uint256);
}
