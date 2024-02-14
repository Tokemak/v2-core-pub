// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract SystemRegistryMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockSysRegAccessController(ISystemRegistry systemRegistry, address accessController) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.accessController.selector),
            abi.encode(accessController)
        );
    }

    function _mockSysRegSystemSecurity(ISystemRegistry systemRegistry, address systemSecurity) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.systemSecurity.selector),
            abi.encode(systemSecurity)
        );
    }
}
