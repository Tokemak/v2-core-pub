// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISequencerChecker } from "src/interfaces/security/ISequencerChecker.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract SequencerChecker is ISequencerChecker, SystemComponent {
    // Half hour grace period after sequencer comes back up.
    uint256 public constant GRACE_PERIOD = 1800;

    IAggregatorV3Interface public immutable sequencerUptimeFeed;

    constructor(
        ISystemRegistry _systemRegistry,
        IAggregatorV3Interface _sequencerUptimeFeed
    ) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(address(_sequencerUptimeFeed), "_sequencerUptimeFeed");
        sequencerUptimeFeed = _sequencerUptimeFeed;
    }

    /// @inheritdoc ISequencerChecker
    function checkSequencerUptimeFeed() external view returns (bool) {
        (uint80 roundId, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();

        if (answer > 1 || roundId == 0 || startedAt == 0) {
            revert Errors.InvalidDataReturned();
        }

        // Check answer. If sequencer is up make sure for appropriate amount of time
        if (answer == 1 || block.timestamp - startedAt < GRACE_PERIOD) {
            return false;
        }
        return true;
    }
}
