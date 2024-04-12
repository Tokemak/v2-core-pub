// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

contract LibAdapterTests is Test {
    TestERC20 private token;

    function setUp() public {
        token = new TestERC20("token", "token");
    }

    function testApproveZeroToNot() public {
        address user1 = vm.addr(1);
        LibAdapter._approve(token, user1, 10);

        uint256 queried = token.allowance(address(this), user1);

        assertEq(queried, 10);
    }

    function testAllowanceGreaterThanZeroLessThanAmount() public {
        address user1 = vm.addr(1);
        LibAdapter._approve(token, user1, 10);
        LibAdapter._approve(token, user1, 30);

        uint256 queried = token.allowance(address(this), user1);

        assertEq(queried, 30);
    }

    function testAllowanceGreaterThanZeroGreaterThanAmount() public {
        address user1 = vm.addr(1);
        LibAdapter._approve(token, user1, 100);
        LibAdapter._approve(token, user1, 30);

        uint256 queried = token.allowance(address(this), user1);

        assertEq(queried, 30);
    }

    function testAllowanceGreaterThanZeroToZero() public {
        address user1 = vm.addr(1);
        LibAdapter._approve(token, user1, 100);
        LibAdapter._approve(token, user1, 30);
        LibAdapter._approve(token, user1, 0);

        uint256 queried = token.allowance(address(this), user1);

        assertEq(queried, 0);
    }

    function testAllowanceIncreasing() public {
        address user1 = vm.addr(1);
        LibAdapter._approve(token, user1, 100);
        LibAdapter._approve(token, user1, 200);

        uint256 queried = token.allowance(address(this), user1);

        assertEq(queried, 200);
    }
}
