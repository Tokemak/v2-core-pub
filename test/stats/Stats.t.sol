// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Stats } from "src/stats/Stats.sol";
import { Errors } from "src/utils/Errors.sol";

contract StatsTest is Test {
    function testComputeAnnualizedChangeMinZero() public {
        _checkComputeAnnualizedChangeMinZero(Stats.SECONDS_IN_YEAR / 2, 1000, Stats.SECONDS_IN_YEAR, 1500, 1e18);
        _checkComputeAnnualizedChangeMinZero(0, 12_345, Stats.SECONDS_IN_YEAR, 20_000, 620_089_104_900_769_542);
        _checkComputeAnnualizedChangeMinZero(0, 5_000_000, 100, 4_999_999, 0);
    }

    function testRevertOnZeroStartValueForComputeAnnualizedChangeMinZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stats.ZeroDivisor.selector));
        Stats.calculateAnnualizedChangeMinZero(0, 0, 1, 1);
    }

    function testRevertOnIncorrectTimestampsForComputeAnnualizedChangeMinZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stats.IncorrectTimestamps.selector));
        Stats.calculateAnnualizedChangeMinZero(0, 1, 0, 10);
    }

    function testFuzzComputeAnnualizedChangeMinZero(
        uint256 startTimestamp,
        uint256 startValue,
        uint256 endTimestamp,
        uint256 endValue
    ) public {
        uint256 divisor = 1e18 * Stats.SECONDS_IN_YEAR; // ensures no overflow
        vm.assume(endTimestamp > startTimestamp);
        vm.assume(startValue < type(uint256).max / divisor);
        vm.assume(startValue > 0);
        vm.assume(endValue < type(uint256).max / divisor);

        // make sure that rounding doesn't drop to zero
        vm.assume(absDiff(startValue, endValue) > 5);
        vm.assume(absDiff(startTimestamp, endTimestamp) < 5 * 365 * 24 * 60 * 60); // 5 years

        uint256 result = Stats.calculateAnnualizedChangeMinZero(startTimestamp, startValue, endTimestamp, endValue);

        if (startValue >= endValue) {
            // negatives are clipped to zero
            assertEq(result, 0);
        } else {
            assertGt(result, 0);
        }
    }

    function testGetFilteredValueRevertIfAlphaTooBig() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "alpha"));
        Stats.getFilteredValue(1e18 + 1, 1, 1);
    }

    function testGetFilteredValueRevertIfAlphaIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "alpha"));
        Stats.getFilteredValue(0, 1, 1);
    }

    function testGetFilteredValueAtExtremes() public {
        uint256 alpha = 1e18;
        uint256 prior = 55e18;
        uint256 current = 1e16;

        uint256 actual = Stats.getFilteredValue(alpha, prior, current);
        assertEq(actual, current);

        alpha = 1;
        actual = Stats.getFilteredValue(alpha, prior, current);
        uint256 expected = (prior * (1e18 - 1) + current) / 1e18;
        assertEq(actual, expected);
    }

    function testGetFilteredValueSuccess() public {
        uint256 alpha = 1e17;
        uint256 prior = 55e18;
        uint256 current = 1e16;

        uint256 expected = (prior * 9e17 + current * 1e17) / 1e18;
        uint256 actual = Stats.getFilteredValue(alpha, prior, current);

        assertEq(actual, expected);
    }

    function _checkComputeAnnualizedChangeMinZero(
        uint256 startTimestamp,
        uint256 startValue,
        uint256 endTimestamp,
        uint256 endValue,
        uint256 expected
    ) private {
        uint256 result = Stats.calculateAnnualizedChangeMinZero(startTimestamp, startValue, endTimestamp, endValue);
        assertEq(result, expected);
    }

    function absDiff(uint256 val1, uint256 val2) private pure returns (uint256) {
        if (val1 > val2) {
            return val1 - val2;
        } else {
            return val2 - val1;
        }
    }
}
