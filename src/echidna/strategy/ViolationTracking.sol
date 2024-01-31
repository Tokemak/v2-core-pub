// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { ViolationTracking } from "src/strategy/ViolationTracking.sol";

contract ViolationTrackingUsage {
    using ViolationTracking for ViolationTracking.State;

    ViolationTracking.State public state;

    bool internal hasReset = false;
    uint256 internal violationsAdded;

    function insert(bool isViolation) external {
        state.insert(isViolation);
        hasReset = false;
        violationsAdded += isViolation ? 1 : 0;
    }

    function addViolations(uint8 x) external {
        for (uint8 i = 0; i < x; i++) {
            state.insert(true);
        }
        violationsAdded += x;
        hasReset = false;
    }

    function reset() external {
        state.reset();
        hasReset = true;
        violationsAdded = 0;
    }
}

contract ViolationTrackingTest is ViolationTrackingUsage {
    function echidna_reset_violation_count_is_zero() public view returns (bool) {
        return hasReset ? state.violationCount == 0 : true;
    }

    function echidna_reset_violations_is_zero() public view returns (bool) {
        return hasReset ? state.violations == 0 : true;
    }

    function echidna_reset_length_is_zero() public view returns (bool) {
        return hasReset ? state.len == 0 : true;
    }

    function echidna_len_less_than_ten() public view returns (bool) {
        return state.len <= 10;
    }

    function echidna_violation_count_less_than_ten() public view returns (bool) {
        return state.violationCount <= 10;
    }
}
