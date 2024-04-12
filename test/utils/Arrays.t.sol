// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";
import { Arrays } from "src/utils/Arrays.sol";

contract ArraysUtilTests is Test {
    address[8] private eight;

    function setUp() public {
        eight[0] = vm.addr(1);
        eight[1] = vm.addr(2);
        eight[2] = vm.addr(3);
        eight[3] = vm.addr(4);
        eight[4] = vm.addr(5);
    }

    function testConvertFixedCurveTokenArrayToDynamic() public {
        address[] memory converted = Arrays.convertFixedCurveTokenArrayToDynamic(eight, 5);

        assertEq(converted.length, 5, "length");
        assertEq(eight[0], converted[0]);
        assertEq(eight[1], converted[1]);
        assertEq(eight[2], converted[2]);
        assertEq(eight[3], converted[3]);
        assertEq(eight[4], converted[4]);
        assertEq(eight[5], address(0));
        assertEq(eight[6], address(0));
        assertEq(eight[7], address(0));
    }
}
