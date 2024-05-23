// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";

/**
 * @notice Cross-contract system-level functionality around pausing and various security features.
 * Allows us to pause all pausable contracts in the system
 * Ensures that operations that change NAV and those that don't are not mixed in the same transaction.
 */
abstract contract SystemSecurity is SystemComponent, SecurityBase, ISystemSecurity {
    bool internal _systemPaused = false;

    event SystemPaused(address account);
    event SystemUnpaused(address account);

    error SystemAlreadyPaused();
    error SystemNotPaused();

    /// @notice How many NAV/share changing operations are in progress in the system
    uint256 public navOpsInProgress = 0;

    modifier onlyAutopool() {
        if (!systemRegistry.autoPoolRegistry().isVault(msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// @inheritdoc ISystemSecurity
    /// @notice Returns true when the entire system is paused
    function isSystemPaused() external virtual returns (bool);

    /// @inheritdoc ISystemSecurity
    /// @notice Enters a NAV/share changing operation from an Autopool
    function enterNavOperation() external override onlyAutopool {
        ++navOpsInProgress;
    }

    /// @inheritdoc ISystemSecurity
    /// @notice Exits a NAV/share changing operation from an Autopool
    function exitNavOperation() external override onlyAutopool {
        --navOpsInProgress;
    }

    /// @notice Pause every pausable contract in the system
    /// @dev Reverts if already paused or not EMERGENCY_PAUSER role
    function pauseSystem() external hasRole(Roles.EMERGENCY_PAUSER) {
        if (_systemPaused) {
            revert SystemAlreadyPaused();
        }
        _systemPaused = true;

        emit SystemPaused(msg.sender);
    }

    /// @notice Unpause every pausable contract in the system that isn't explicitly paused
    /// @dev Reverts if system not paused or not EMERGENCY_PAUSER role.
    function unpauseSystem() external hasRole(Roles.EMERGENCY_PAUSER) {
        if (!_systemPaused) {
            revert SystemNotPaused();
        }
        _systemPaused = false;

        emit SystemUnpaused(msg.sender);
    }
}
