// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { SystemSecurityL1 } from "src/security/SystemSecurityL1.sol";
import {
    SystemSecurityBaseTests,
    SystemSecurity,
    SystemRegistry,
    AccessController,
    IAutopoolRegistry
} from "test/security/SystemSecurityBase.t.sol";

contract SystemSecurityL1Tests is SystemSecurityBaseTests {
    function setUp() public {
        _systemRegistry = new SystemRegistry(vm.addr(100), vm.addr(101));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _accessController.grantRole(Roles.EMERGENCY_PAUSER, address(this));

        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        _mockIsVault(address(this), true);

        _systemSecurity = SystemSecurity(new SystemSecurityL1(_systemRegistry));
        _systemRegistry.setSystemSecurity(address(_systemSecurity));
    }
}
