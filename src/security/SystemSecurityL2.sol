// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract SystemSecurityL2 is SystemSecurity {
    /// @notice Used in the case of an issue with sequencer uptime reports
    bool public overrideSequencerUptime = false;

    /// @notice Thrown when sequencer cannot be overridden
    error CannotOverride();

    /// @notice Emitted when sequencer override is set
    event SequencerOverrideSet(bool overrideStatus);

    constructor(ISystemRegistry _systemRegsitry) SystemSecurity(_systemRegsitry) { }

    /// @inheritdoc SystemSecurity
    function isSystemPaused() external override returns (bool) {
        if (_systemPaused) {
            return true;
        }

        if (!systemRegistry.sequencerChecker().checkSequencerUptimeFeed() && !overrideSequencerUptime) {
            return true;
        }

        // If we get to here the system is not paused, and we want to undo any override that we may have.
        if (overrideSequencerUptime == true) {
            emit SequencerOverrideSet(false);
            overrideSequencerUptime = false;
        }
        return false;
    }

    /// @notice Allows us to override sequencer being down.  This is a failsafe in case something goes wrong with
    ///   the Chainlink feed.
    function setOverrideSequencerUptime() external hasRole(Roles.SEQUENCER_OVERRIDE_MANAGER) {
        // If sequencer is up, cannot override
        if (systemRegistry.sequencerChecker().checkSequencerUptimeFeed()) {
            revert CannotOverride();
        }

        overrideSequencerUptime = true;
        emit SequencerOverrideSet(true);
    }
}
