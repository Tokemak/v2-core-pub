// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase */

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Test } from "forge-std/Test.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { IAutoPoolRegistry } from "src/interfaces/vault/IAutoPoolRegistry.sol";

contract SystemSecurityTests is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    SystemSecurity private _systemSecurity;

    IAutoPoolRegistry private _autoPoolRegistry;

    event SystemPaused(address account);
    event SystemUnpaused(address account);

    function setUp() public {
        _systemRegistry = new SystemRegistry(vm.addr(100), vm.addr(101));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        _accessController.grantRole(Roles.EMERGENCY_PAUSER, address(this));

        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutoPoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutoPoolRegistry(address(_autoPoolRegistry));

        _mockIsVault(address(this), true);
    }

    function test_isSystemPaused_IsFalseByDefault() public {
        assertEq(_systemSecurity.isSystemPaused(), false);
    }

    function test_pauseSystem_SetIsSystemPausedToTrue() public {
        assertEq(_systemSecurity.isSystemPaused(), false);
        _systemSecurity.pauseSystem();
        assertEq(_systemSecurity.isSystemPaused(), true);
    }

    function test_pauseSystem_RevertsIf_PausingWhenAlreadyPaused() public {
        _systemSecurity.pauseSystem();
        vm.expectRevert(abi.encodeWithSelector(SystemSecurity.SystemAlreadyPaused.selector));
        _systemSecurity.pauseSystem();
    }

    function test_pauseSystem_EmitsSystemPausedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SystemPaused(address(this));
        _systemSecurity.pauseSystem();
    }

    function test_pauseSystem_RevertsIf_CallerDoesNotHaveRole() public {
        address caller = vm.addr(5);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _systemSecurity.pauseSystem();
        vm.stopPrank();

        _systemSecurity.pauseSystem();
    }

    function test_unpauseSystem_SetIsSystemPausedToFalse() public {
        _systemSecurity.pauseSystem();
        assertEq(_systemSecurity.isSystemPaused(), true);
        _systemSecurity.unpauseSystem();
        assertEq(_systemSecurity.isSystemPaused(), false);
    }

    function test_unpauseSystem_RevertsIf_UnpausingWhenNotAlreadyPaused() public {
        _systemSecurity.pauseSystem();
        _systemSecurity.unpauseSystem();
        vm.expectRevert(abi.encodeWithSelector(SystemSecurity.SystemNotPaused.selector));
        _systemSecurity.unpauseSystem();
    }

    function test_unpauseSystem_EmitsSystemUnpausedEvent() public {
        _systemSecurity.pauseSystem();

        vm.expectEmit(true, true, true, true);
        emit SystemUnpaused(address(this));
        _systemSecurity.unpauseSystem();
    }

    function test_unpauseSystem_RevertsIf_CallerDoesNotHaveRole() public {
        _systemSecurity.pauseSystem();

        address caller = vm.addr(5);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _systemSecurity.unpauseSystem();
        vm.stopPrank();

        _systemSecurity.unpauseSystem();
    }

    function test_enterNavOperation_IncrementsOperationCounter() public {
        assertEq(_systemSecurity.navOpsInProgress(), 0);
        _systemSecurity.enterNavOperation();
        assertEq(_systemSecurity.navOpsInProgress(), 1);
    }

    function test_enterNavOperation_CanBeCalledMultipleTimes() public {
        _systemSecurity.enterNavOperation();
        _systemSecurity.enterNavOperation();
        assertEq(_systemSecurity.navOpsInProgress(), 2);
        _systemSecurity.exitNavOperation();
        _systemSecurity.exitNavOperation();
        assertEq(_systemSecurity.navOpsInProgress(), 0);
    }

    function test_enterNavOperation_CanOnlyBeCalledByAutoPool() public {
        _mockIsVault(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _systemSecurity.enterNavOperation();

        _mockIsVault(address(this), true);
        _systemSecurity.enterNavOperation();
    }

    function test_exitNavOperation_DecrementsOperationCounter() public {
        assertEq(_systemSecurity.navOpsInProgress(), 0);
        _systemSecurity.enterNavOperation();
        assertEq(_systemSecurity.navOpsInProgress(), 1);
        _systemSecurity.exitNavOperation();
        assertEq(_systemSecurity.navOpsInProgress(), 0);
    }

    function test_exitNavOperation_CantBeCalledMoreThanExit() public {
        _systemSecurity.enterNavOperation();
        _systemSecurity.enterNavOperation();
        _systemSecurity.exitNavOperation();
        _systemSecurity.exitNavOperation();
        vm.expectRevert();
        _systemSecurity.exitNavOperation();
    }

    function test_exitNavOperation_CanOnlyBeCalledByAutoPool() public {
        _systemSecurity.enterNavOperation();

        _mockIsVault(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _systemSecurity.exitNavOperation();

        _mockIsVault(address(this), true);
        _systemSecurity.exitNavOperation();
    }

    function _mockSystemBound(address registry, address addr) internal {
        vm.mockCall(addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(registry));
    }

    function _mockIsVault(address vault, bool isVault) internal {
        vm.mockCall(
            address(_autoPoolRegistry),
            abi.encodeWithSelector(IAutoPoolRegistry.isVault.selector, vault),
            abi.encode(isVault)
        );
    }
}
