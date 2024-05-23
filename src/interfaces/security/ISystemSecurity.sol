// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

interface ISystemSecurity {
    /// @notice Get the number of NAV/share operations currently in progress
    /// @return Number of operations
    function navOpsInProgress() external view returns (uint256);

    /// @notice Called at the start of any NAV/share changing operation
    function enterNavOperation() external;

    /// @notice Called at the end of any NAV/share changing operation
    function exitNavOperation() external;

    /// @notice Whether or not the system as a whole is paused
    function isSystemPaused() external returns (bool);
}
