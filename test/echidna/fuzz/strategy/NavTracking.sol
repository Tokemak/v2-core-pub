// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { NavTracking } from "src/strategy/NavTracking.sol";

contract NavTrackingUsage {
    using NavTracking for NavTracking.State;

    NavTracking.State public state;

    uint256 internal latestNavPerShareAdded;
    uint256 internal latestIndex;

    function insert(uint256 navPerShare, uint40 timestamp) external {
        if (timestamp > state.lastFinalizedTimestamp) {
            state.insert(navPerShare, timestamp);
            latestNavPerShareAdded = navPerShare;
            latestIndex = state.currentIndex;
        }
    }

    function getDaysAgo(uint8 daysAgo) public view returns (uint256) {
        return state.getDaysAgo(daysAgo);
    }
}

contract NavTrackingTest is NavTrackingUsage {
    function echidna_maxlength_under_ninety_one() public view returns (bool) {
        return state.len <= 91;
    }

    function echidna_last_add_always_latest() public view returns (bool) {
        return latestNavPerShareAdded == 0 || getDaysAgo(0) == latestNavPerShareAdded;
    }

    function echidna_test_index_matches_latest() public view returns (bool) {
        return state.history[latestIndex] == latestNavPerShareAdded;
    }
}
