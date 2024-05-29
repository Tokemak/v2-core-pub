// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemSecurity, Errors } from "src/security/SystemSecurity.sol";
import { ISequencerChecker } from "src/interfaces/security/ISequencerChecker.sol";

contract SystemSecurityL2 is SystemSecurity {
    /// @notice Used in the case of an issue with sequencer uptime reports
    bool public overrideSequencerUptime = false;

    /// @notice Thrown when sequencer cannot be overridden
    error CannotOverride();

    /// @notice Emitted when sequencer override is set
    event SequencerOverrideSet(bool overrideStatus);

    // slither-disable-next-line similar-names
    constructor(ISystemRegistry _systemRegsitry) SystemSecurity(_systemRegsitry) { }

    /// @inheritdoc SystemSecurity
    function isSystemPaused() external override returns (bool) {
        // Check admin controlled system pause
        if (_systemPaused) {
            return true;
        }

        // Check sequencer controlled system pause, ensure that we are not overriding the sequencer return
        ISequencerChecker checker = systemRegistry.sequencerChecker();
        Errors.verifyNotZero(address(checker), "checker");
        bool sequencerStatus = checker.checkSequencerUptimeFeed();

        // Sequencer down, override false
        if (!sequencerStatus && !overrideSequencerUptime) {
            return true;
        }

        // Sequencer up, override true
        if (sequencerStatus && overrideSequencerUptime) {
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
