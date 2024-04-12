// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase,contract-name-camelcase */

import { Test } from "forge-std/Test.sol";
import { Numbers } from "test/echidna/fuzz/utils/Numbers.sol";

// solhint-disable func-name-mixedcase

contract NumbersTests is Test, Numbers {
    function test_tweak_MinValueTakesNumberToZero() public {
        uint256 x = 1e18;
        uint256 output = tweak(x, type(int8).min);

        assertTrue(x > 0, "input");
        assertEq(output, 0, "zero");
    }

    function test_tweak_MaxValueDoublesNumber() public {
        uint256 x = 1e18;
        uint256 output = tweak(x, type(int8).max);

        assertEq(output, x * 2, "double");
    }

    function test_tweak_MidPositiveValue() public {
        uint256 x = 1e18;
        uint256 output = tweak(x, 51); // Roughly 40%

        assertApproxEqAbs(1.4e18, output, 0.01e18, "new");
    }

    function test_tweak_MidNegativeValue() public {
        uint256 x = 1e18;
        uint256 output = tweak(x, -51); // Roughly 40%

        assertApproxEqAbs(0.6e18, output, 0.01e18, "new");
    }

    function test_scaleTo_MinValue() public {
        uint8 bin = 0;
        uint256 max = 3;

        assertEq(scaleTo(bin, max), 0);
    }

    function test_scaleTo_MaxValue() public {
        uint8 bin = type(uint8).max;
        uint256 max = 3;

        assertEq(scaleTo(bin, max), 3);
    }

    function test_scaleTo_MaxValueMinusOneInLargestBucket() public {
        uint8 bin = type(uint8).max - 1;
        uint256 max = 3;

        assertEq(scaleTo(bin, max), 3);
    }

    function testFuzz_NumbersBucket(uint8 bin) public {
        uint256 max = 3;

        // Max val of 3, 4 buckets
        uint256 answer;
        if (bin < 64) {
            answer = 0;
        } else if (bin >= 64 && bin < 128) {
            answer = 1;
        } else if (bin >= 128 && bin < 192) {
            answer = 2;
        } else if (bin >= 192) {
            answer = 3;
        }

        assertEq(scaleTo(bin, max), answer);
    }
}
