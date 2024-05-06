// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { Utilities } from "src/libs/Utilities.sol";

contract UtilitiesTest is Test {
    function test_getScaleDownFactor() public {
        // >18 decimals
        assertFactors(24, 1e21, 1e3);

        // 18 decimals
        assertFactors(18, 1e15, 1e3);

        // >=6 <18 decimals
        assertFactors(17, 1e15, 1e2);
        assertFactors(9, 1e7, 1e2);
        assertFactors(6, 1e4, 1e2);

        // <6 >=2 decimals
        assertFactors(5, 1e4, 1e1);
        assertFactors(3, 1e2, 1e1);
        assertFactors(2, 1e1, 1e1);

        // <2 decimals
        assertFactors(1, 10, 1);
        assertFactors(0, 1, 1);
    }

    function assertFactors(uint8 decimals, uint256 scaledDownUnit, uint256 padUnit) internal {
        (uint256 actualScaledDownUnit, uint256 actualPadUnit) = Utilities.getScaleDownFactor(decimals);
        assertEq(actualScaledDownUnit, scaledDownUnit, "scaledDownUnit");
        assertEq(padUnit, actualPadUnit, "padUnit");
    }
}
