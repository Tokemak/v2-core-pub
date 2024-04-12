// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase
// solhint-disable max-states-count

import { Test } from "forge-std/Test.sol";
import { Ownable2Step } from "src/access/Ownable2Step.sol";

contract Ownable2StepTest is Test {
    OwnableOps private ops;

    function setUp() public {
        ops = new OwnableOps();
    }

    function test_renounceOwner_IsNotPermitted() public {
        vm.expectRevert();
        ops.renounceOwnership();

        ops.run();
        assertTrue(ops.ran());
    }

    function test_onlyOwner_ProtectsFunctions() public {
        assertTrue(!ops.ran());

        vm.startPrank(address(6));
        vm.expectRevert();
        ops.run();
        vm.stopPrank();

        assertTrue(!ops.ran());
        ops.run();
        assertTrue(ops.ran());
    }
}

contract OwnableOps is Ownable2Step {
    bool public ran;

    function run() external onlyOwner {
        ran = true;
    }
}
