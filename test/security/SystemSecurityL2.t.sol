// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { SystemSecurityL2, Errors } from "src/security/SystemSecurityL2.sol";
import {
    SystemSecurityBaseTests,
    SystemSecurity,
    SystemRegistry,
    AccessController,
    IAutopoolRegistry
} from "test/security/SystemSecurityBase.t.sol";
import { SystemRegistryL2, ISystemRegistryL2 } from "src/SystemRegistryL2.sol";

// solhint-disable func-name-mixedcase

contract SystemSecurityL2Tests is SystemSecurityBaseTests {
    event SequencerOverrideSet(bool overrideStatus);

    MockSequencerChecker public checker;

    function setUp() public virtual {
        _systemRegistry = SystemRegistry(address(new SystemRegistryL2(vm.addr(100), vm.addr(101))));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _accessController.grantRole(Roles.EMERGENCY_PAUSER, address(this));

        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        _mockIsVault(address(this), true);

        _systemSecurity = SystemSecurity(new SystemSecurityL2(_systemRegistry));
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        checker = new MockSequencerChecker();

        _mockSystemBound(address(_systemRegistry), address(checker));
        SystemRegistryL2(address(_systemRegistry)).setSequencerChecker(address(checker));

        // Some underlying tests hit path of calling sequencer, return true for all
        checker.setSequencerReturnValue(true);
    }

    function _mockHasRoleSequencerOverrideManager(bool hasRole) internal {
        vm.mockCall(
            address(_accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.SEQUENCER_OVERRIDE_MANAGER, address(this)),
            abi.encode(hasRole)
        );
    }
}

contract SetOverrideSequencerUptimeTests is SystemSecurityL2Tests {
    function test_RevertIf_NotSequencerOverrideManager() public {
        _mockHasRoleSequencerOverrideManager(false);

        vm.expectRevert(Errors.AccessDenied.selector);
        SystemSecurityL2(address(_systemSecurity)).setOverrideSequencerUptime();
    }

    function test_RevertIf_SequencerUp() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(true);

        vm.expectRevert(SystemSecurityL2.CannotOverride.selector);
        SystemSecurityL2(address(_systemSecurity)).setOverrideSequencerUptime();
    }

    function test_SetsStateToTrue_EmitsEvent_WhenSequencerDown() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(false);

        vm.expectEmit(true, true, true, true);
        emit SequencerOverrideSet(true);
        SystemSecurityL2(address(_systemSecurity)).setOverrideSequencerUptime();

        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), true);
    }
}

contract IsSystemPausedTests is SystemSecurityL2Tests {
    function test_RevertIf_ZeroAddress() public {
        vm.mockCall(
            address(_systemRegistry),
            abi.encodeWithSelector(ISystemRegistryL2.sequencerChecker.selector),
            abi.encode(address(0))
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "checker"));
        _systemSecurity.isSystemPaused();
    }

    function test_ReturnsTrue_AdminSystemPause() public {
        vm.mockCall(
            address(_accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.EMERGENCY_PAUSER, address(this)),
            abi.encode(true)
        );

        _systemSecurity.pauseSystem();

        bool returnVal = _systemSecurity.isSystemPaused();
        assertEq(returnVal, true);
    }

    // System paused (returns true), override does not change
    function test_SequencerDown_OverrideFalse() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(false);

        bool overrideSequencerBefore = SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime();
        assertEq(overrideSequencerBefore, false);

        bool retValue = _systemSecurity.isSystemPaused();

        assertEq(retValue, true);
        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), overrideSequencerBefore);
    }

    // System not paused (returns false), override does not change
    function test_SequencerDown_OverrideTrue() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(false);

        vm.expectEmit(true, true, true, true);
        emit SequencerOverrideSet(true);
        SystemSecurityL2(address(_systemSecurity)).setOverrideSequencerUptime();

        bool overrideSequencerBefore = SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime();
        assertEq(overrideSequencerBefore, true);

        bool retValue = _systemSecurity.isSystemPaused();

        assertEq(retValue, false);
        // Shouldn't change when sequencer returning false
        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), overrideSequencerBefore);
    }

    // System not paused (returns false), override does not change
    function test_SequencerUp_OverrideFalse() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(true);

        bool overrideSequencerBefore = SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime();
        assertEq(overrideSequencerBefore, false);

        bool retValue = _systemSecurity.isSystemPaused();

        assertEq(retValue, false);
        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), overrideSequencerBefore);
    }

    // System not paused (returns false) and override is reset to false
    function test_SequencerUp_OverrideTrue() public {
        _mockHasRoleSequencerOverrideManager(true);
        checker.setSequencerReturnValue(false);

        vm.expectEmit(true, true, true, true);
        emit SequencerOverrideSet(true);
        SystemSecurityL2(address(_systemSecurity)).setOverrideSequencerUptime();

        checker.setSequencerReturnValue(true);
        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), true);

        vm.expectEmit(true, true, true, true);
        emit SequencerOverrideSet(false);
        bool retValue = _systemSecurity.isSystemPaused();

        assertEq(retValue, false);
        assertEq(SystemSecurityL2(address(_systemSecurity)).overrideSequencerUptime(), false);
    }
}

contract MockSequencerChecker {
    bool public sequencerReturnValue;

    function checkSequencerUptimeFeed() external view returns (bool) {
        return sequencerReturnValue;
    }

    function setSequencerReturnValue(bool set) external {
        sequencerReturnValue = set;
    }
}
