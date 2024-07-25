// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Errors } from "src/utils/Errors.sol";
import { Test } from "forge-std/Test.sol";
import { SystemRegistryL2 } from "src/SystemRegistryL2.sol";
import { SystemRegistryBase } from "src/SystemRegistryBase.sol";
import { TOKE_MAINNET, WETH_MAINNET, RANDOM } from "test/utils/Addresses.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";

// solhint-disable func-name-mixedcase

contract SystemRegistryL2Test is Test {
    SystemRegistryL2 private _systemRegistryL2;

    function setUp() public {
        //Setup L2 toke address with same address as L1
        _systemRegistryL2 = new SystemRegistryL2(TOKE_MAINNET, WETH_MAINNET);
    }

    function testSystemRegistryL2SetToke() public {
        address token = RANDOM;
        mockSystemComponent(token);
        _systemRegistryL2.setToke(token);
        assertEq(address(_systemRegistryL2.toke()), token);
    }

    function testSystemRegistryL2SetTokeZeroAddress() public {
        address token = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newToke"));
        _systemRegistryL2.setToke(token);
    }

    function testSystemRegistryL2SetTokeDuplicateSet() public {
        address token = RANDOM;
        mockSystemComponent(token);
        _systemRegistryL2.setToke(token);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, token));
        _systemRegistryL2.setToke(token);
    }

    /* ******************************** */
    /* Helpers
    /* ******************************** */

    function mockSystemComponent(address addr) internal {
        vm.mockCall(
            addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(_systemRegistryL2)
        );
    }
}
