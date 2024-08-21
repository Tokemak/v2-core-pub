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

    function _mockSysRegStatCalcRegistry(ISystemRegistry systemRegistry, address statCalcRegistry) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.statsCalculatorRegistry.selector),
            abi.encode(statCalcRegistry)
        );
    }

    function _mockSysRegSystemSecurity(ISystemRegistry systemRegistry, address systemSecurity) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.systemSecurity.selector),
            abi.encode(systemSecurity)
        );
    }

    function _mockSysRegReceivingRouter(ISystemRegistry systemRegistry, address receivingRouter) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.receivingRouter.selector),
            abi.encode(receivingRouter)
        );
    }

    function _mockSysRegRootPriceOracle(ISystemRegistry systemRegistry, address rootPriceOracle) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector),
            abi.encode(rootPriceOracle)
        );
    }

    function _mockSysRegMessageProxy(ISystemRegistry systemRegistry, address messageProxy) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.messageProxy.selector),
            abi.encode(messageProxy)
        );
    }

    function _mockSysRegDestVaultRegistry(ISystemRegistry systemRegistry, address destinationVaultRegistry) internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.destinationVaultRegistry.selector),
            abi.encode(destinationVaultRegistry)
        );
    }
}
