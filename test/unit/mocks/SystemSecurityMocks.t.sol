// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";

contract SystemSecurityMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockSysSecurityInit(ISystemSecurity systemSecurity) internal {
        _mockSysSecurityNavOpsInProgress(systemSecurity, 0);
        _mockSysSecurityIsSystemPaused(systemSecurity, false);

        vm.mockCall(
            address(systemSecurity), abi.encodeWithSelector(ISystemSecurity.enterNavOperation.selector), abi.encode()
        );
        vm.mockCall(
            address(systemSecurity), abi.encodeWithSelector(ISystemSecurity.exitNavOperation.selector), abi.encode()
        );
    }

    function _mockSysSecurityIsSystemPaused(ISystemSecurity systemSecurity, bool paused) internal {
        vm.mockCall(
            address(systemSecurity), abi.encodeWithSelector(ISystemSecurity.isSystemPaused.selector), abi.encode(paused)
        );
    }

    function _mockSysSecurityNavOpsInProgress(ISystemSecurity systemSecurity, uint256 num) internal {
        vm.mockCall(
            address(systemSecurity), abi.encodeWithSelector(ISystemSecurity.navOpsInProgress.selector), abi.encode(num)
        );
    }
}
