// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { NavTracking } from "src/strategy/NavTracking.sol";

// solhint-disable func-name-mixedcase

contract NavTrackingTest is Test {
    using NavTracking for NavTracking.State;

    NavTracking.State private state;

    function setUp() public {
        NavTracking.State memory _state;
        state = _state;
    }

    function test_singleInsert() public {
        state.insert(100, 1 days);

        assertEq(state.getDaysAgo(0), 100);
        assertEq(state.len, 1);
    }

    function test_insertsDuringSameDay() public {
        uint40 startTimestamp = uint40(1 days);
        state.insert(100, startTimestamp); // initialize on the first insert
        state.insert(101, startTimestamp + 1);
        state.insert(102, startTimestamp + 2);
        assertEq(state.getDaysAgo(0), 102);

        uint40 nextDayInsert = startTimestamp + uint40(1 days);
        state.insert(105, nextDayInsert);
        state.insert(107, nextDayInsert + uint40(1 days) - 1);
        assertEq(state.getDaysAgo(0), 107);
        assertEq(state.getDaysAgo(1), 102);
    }

    function test_RevertIf_invalidTimestamp() public {
        state.insert(100, 1 days);

        vm.expectRevert(abi.encodeWithSelector(NavTracking.InvalidNavTimestamp.selector, 1 days, 1));
        state.insert(100, 1);
    }

    function test_RevertIf_insufficientHistory() public {
        state.insert(100, 1 days);
        vm.expectRevert(abi.encodeWithSelector(NavTracking.NavHistoryInsufficient.selector));
        state.getDaysAgo(1);
    }
}
