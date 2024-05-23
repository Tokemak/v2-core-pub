// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase */

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { Pausable } from "src/security/Pausable.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Test } from "forge-std/Test.sol";
import { SystemSecurityL1 } from "src/security/SystemSecurityL1.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";

contract PausableTests is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    SystemSecurityL1 private _systemSecurity;

    PausableMock private _pausable;

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        _systemRegistry = new SystemRegistry(vm.addr(100), vm.addr(101));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _systemSecurity = new SystemSecurityL1(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        _pausable = new PausableMock(_systemRegistry);

        _accessController.grantRole(Roles.EMERGENCY_PAUSER, address(this));
    }

    function test_paused_ReturnsTrueLocallyPaused() public {
        _pausable.pause();
        assertEq(_pausable.paused(), true);
    }

    function test_paused_ReturnsFalseWhenNotLocallyOrSystemPaused() public {
        _pausable.pause();
        _pausable.unpause();
        assertEq(_pausable.paused(), false);
    }

    function test_paused_ReturnsTrueWhenLocallyNotPausedButSystemPaused() public {
        assertEq(_pausable.paused(), false);
        _systemSecurity.pauseSystem();
        assertEq(_pausable.paused(), true);
        _systemSecurity.unpauseSystem();
        assertEq(_pausable.paused(), false);
    }

    function test_pause_CanPerformNormalProcessInNonPause() public {
        assertEq(_pausable.count(), 0);
        _pausable.normalProcess();
        assertEq(_pausable.count(), 1);
    }

    function test_pause_CannotTakeDrasticMeasureInNonPause() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsNotPaused.selector));
        _pausable.drasticMeasure();
        assertEq(_pausable.drasticMeasureTaken(), false);
    }

    function test_pause_EmitsPausedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Paused(address(this));
        _pausable.pause();
    }

    function test_pause_CannotPerformNormalProcessInPause() public {
        _pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        _pausable.normalProcess();
    }

    function test_pause_CanTakeADrasticMeasureInAPause() public {
        _pausable.pause();
        _pausable.drasticMeasure();
        assertEq(_pausable.drasticMeasureTaken(), true);
    }

    function test_pause_RevertsIf_PausingWhenAlreadyPaused() public {
        _pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        _pausable.pause();
    }

    function test_pause_RevertsIf_CallerDoesNotHaveRole() public {
        address caller = vm.addr(5);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _pausable.pause();
        vm.stopPrank();

        _pausable.pause();
    }

    function test_unpause_CanBeUnpausedWhenPaused() public {
        _pausable.pause();
        assertEq(_pausable.paused(), true);
        _pausable.unpause();
        assertEq(_pausable.paused(), false);
    }

    function test_unpause_EmitsUnpausedEvent() public {
        _pausable.pause();
        vm.expectEmit(true, true, true, true);
        emit Unpaused(address(this));
        _pausable.unpause();
    }

    function test_unpause_ShouldResumeAllowingNormalProcess() public {
        assertEq(_pausable.count(), 0);
        _pausable.pause();
        _pausable.unpause();
        _pausable.normalProcess();
        assertEq(_pausable.count(), 1);
    }

    function test_unpause_ShouldPreventDrasticMeasure() public {
        _pausable.pause();
        _pausable.unpause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsNotPaused.selector));
        _pausable.drasticMeasure();
        assertEq(_pausable.drasticMeasureTaken(), false);
    }

    function test_unpause_RevertsIf_UnpausingWhenNotAlreadyPaused() public {
        _pausable.pause();
        _pausable.unpause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsNotPaused.selector));
        _pausable.unpause();
    }

    function test_unpause_RevertsIf_CallerDoesNotHaveRole() public {
        _pausable.pause();

        address caller = vm.addr(5);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _pausable.unpause();
        vm.stopPrank();

        _pausable.unpause();
    }
}

contract PausableMock is Pausable {
    bool public drasticMeasureTaken;
    uint256 public count;

    constructor(ISystemRegistry systemRegistry) Pausable(systemRegistry) {
        drasticMeasureTaken = false;
        count = 0;
    }

    function normalProcess() external whenNotPaused {
        count++;
    }

    function drasticMeasure() external whenPaused {
        drasticMeasureTaken = true;
    }
}
