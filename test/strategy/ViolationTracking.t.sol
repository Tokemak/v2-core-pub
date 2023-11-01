// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { ViolationTracking } from "src/strategy/ViolationTracking.sol";

contract ViolationTrackingTest is Test {
    using ViolationTracking for ViolationTracking.State;

    ViolationTracking.State private state;

    function setUp() public {
        ViolationTracking.State memory _state;
        state = _state;
    }

    function testBasicInsertAndViolationCount() public {
        assertEq(state.len, 0);
        assertEq(state.violations, 0);
        assertEq(state.violationCount, 0);

        state.insert(true);
        assertEq(state.violationCount, 1);
        assertEq(state.len, 1);

        state.insert(false);
        state.insert(true);
        assertEq(state.violationCount, 2);
        assertEq(state.len, 3);
    }

    function testLargerThanCapacityInserts() public {
        state.insert(true);
        state.insert(false);

        // active
        state.insert(true);
        state.insert(true);
        state.insert(true);
        state.insert(false);
        state.insert(true);
        state.insert(false);
        state.insert(true);
        state.insert(true);
        state.insert(true);
        state.insert(true);

        assertEq(state.violationCount, 8);
        assertEq(state.len, 10);
    }

    function testReset() public {
        assertEq(state.len, 0);
        assertEq(state.violations, 0);
        assertEq(state.violationCount, 0);

        state.insert(true);
        state.insert(true);
        state.insert(true);
        state.insert(false);
        state.insert(true);

        assertEq(state.len, 5);
        assertEq(state.violationCount, 4);

        state.reset();
        assertEq(state.len, 0);
        assertEq(state.violations, 0);
        assertEq(state.violationCount, 0);
    }

    function testFuzzInsertsAndViolationCount(bool[] memory toInsert) public {
        for (uint256 i = 0; i < toInsert.length; ++i) {
            state.insert(toInsert[i]);
        }

        uint8 violationCount = countViolations(toInsert);
        assertEq(state.violationCount, violationCount);
    }

    // metric | array | uint16 |
    // ------ | ----- | ------ |
    // min    | 1849  | 612    |
    // avg    | 4529  | 2276   |
    // median | 2393  | 1265   |
    // max    | 45773 | 23165  |
    function testGasUsage() public {
        ViolationTrackingGasChecker tracker = new ViolationTrackingGasChecker();
        // 20 total inserts
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(false);
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(false);
        tracker.insert(false);
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(false);
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(true);
        tracker.insert(false);
        tracker.insert(false);
        tracker.insert(true);
        tracker.insert(false);
        tracker.insert(true);
        tracker.insert(true);
    }

    function countViolations(bool[] memory inserted) private pure returns (uint8) {
        uint256 numInserts = inserted.length;

        uint8 maxCount = 10;
        if (numInserts < maxCount) {
            maxCount = uint8(numInserts);
        }

        uint8 violationCount = 0;
        for (uint256 i = 0; i < maxCount; ++i) {
            if (inserted[numInserts - i - 1]) {
                violationCount += 1;
            }
        }

        return violationCount;
    }
}

// Forge won't generate a gas report for the library execution
contract ViolationTrackingGasChecker {
    using ViolationTracking for ViolationTracking.State;

    ViolationTracking.State public state;

    function insert(bool isViolation) public {
        state.insert(isViolation);
    }
}
