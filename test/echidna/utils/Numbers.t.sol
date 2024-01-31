// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { Numbers } from "src/echidna/utils/Numbers.sol";

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
}
