// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISystemBound } from "src/interfaces/ISystemBound.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

/// @notice Track stat calculators for this instance of the system
interface IStatsCalculatorRegistry is ISystemBound {
    /// @notice Get a registered calculator
    /// @dev Should revert if missing
    /// @param aprId key of the calculator to get
    /// @return calculator instance of the calculator
    function getCalculator(bytes32 aprId) external view returns (IStatsCalculator calculator);

    /// @notice Register a new stats calculator
    /// @param calculator address of the calculator
    function register(address calculator) external;
}
