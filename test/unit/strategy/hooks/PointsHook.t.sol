// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { PointsHook } from "src/strategy/hooks/PointsHook.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IAutopoolStrategy } from "src/interfaces/strategy/IAutopoolStrategy.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { DestinationVaultRegistryMocks } from "test/unit/mocks/DestinationVaultRegistryMocks.t.sol";

// solhint-disable func-name-mixedcase,contract-name-camelcase

contract PointsHookTests is Test, SystemRegistryMocks, AccessControllerMocks, DestinationVaultRegistryMocks {
    ISystemRegistry internal _systemRegistry;
    IAccessController internal _accessController;
    IDestinationVaultRegistry internal _destVaultRegistry;

    PointsHook internal _hook;

    error BoostExceedsMax(address destinationVault, uint256 providedValue);

    event BoostsSet(address[] destinationVaults, uint256[] boosts);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) DestinationVaultRegistryMocks(vm) { }

    function setUp() public {
        _systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        _accessController = IAccessController(makeAddr("accessController"));
        _destVaultRegistry = IDestinationVaultRegistry(makeAddr("destVaultRegistry"));

        _mockSysRegAccessController(_systemRegistry, address(_accessController));
        _mockSysRegDestVaultRegistry(_systemRegistry, address(_destVaultRegistry));

        _hook = new PointsHook(_systemRegistry, 0.1e18);
    }

    function _mockIsPointsAdmin(address user, bool isAdmin) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.STATS_HOOK_POINTS_ADMIN, isAdmin);
    }
}

contract Constructor is PointsHookTests {
    function test_SetUpState() public {
        assertEq(_hook.getSystemRegistry(), address(_systemRegistry));
    }

    function test_RevertIf_MaxBoostIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxBoost"));
        new PointsHook(_systemRegistry, 0);
    }
}

contract SetBoosts is PointsHookTests {
    function test_RevertIf_ParamsAreEmpty() external {
        _mockIsPointsAdmin(address(this), true);
        address[] memory destinationVaults = new address[](0);
        uint256[] memory boosts = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "boostsLen"));
        _hook.setBoosts(destinationVaults, boosts);
    }

    function test_RevertIf_ArraysDontMatchLength() external {
        _mockIsPointsAdmin(address(this), true);
        address[] memory destinationVaults = new address[](1);
        uint256[] memory boosts = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2, "boosts"));
        _hook.setBoosts(destinationVaults, boosts);
    }

    function test_RevertIf_DestinationVaultIsntRegistered() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(0), false);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), false);
        address[] memory destinationVaults = new address[](1);
        uint256[] memory boosts = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));
        _hook.setBoosts(destinationVaults, boosts);

        destinationVaults[0] = address(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));
        _hook.setBoosts(destinationVaults, boosts);
    }

    function test_RevertIf_BoostExceedsMax() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](1);
        uint256[] memory boosts = new uint256[](1);

        destinationVaults[0] = address(1);
        boosts[0] = _hook.maxBoost() + 1;
        vm.expectRevert(abi.encodeWithSelector(PointsHook.BoostExceedsMax.selector, destinationVaults[0], boosts[0]));
        _hook.setBoosts(destinationVaults, boosts);
    }

    function test_RevertIf_NotCalledByRole() external {
        address badUser = makeAddr("badUser");
        _mockIsPointsAdmin(badUser, false);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](1);
        uint256[] memory boosts = new uint256[](1);

        destinationVaults[0] = address(1);
        boosts[0] = _hook.maxBoost();

        vm.startPrank(badUser);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _hook.setBoosts(destinationVaults, boosts);

        vm.stopPrank();
    }

    function test_SavesValues() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](2);
        uint256[] memory boosts = new uint256[](2);

        destinationVaults[0] = address(1);
        destinationVaults[1] = address(2);
        boosts[0] = _hook.maxBoost();
        boosts[1] = 1;

        _hook.setBoosts(destinationVaults, boosts);

        assertEq(_hook.destinationBoosts(address(1)), _hook.maxBoost(), "value");
        assertEq(_hook.destinationBoosts(address(2)), 1, "value2");
    }

    function test_EmitsEvent() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](2);
        uint256[] memory boosts = new uint256[](2);

        destinationVaults[0] = address(1);
        destinationVaults[1] = address(2);
        boosts[0] = _hook.maxBoost();
        boosts[1] = 1;

        vm.expectEmit(true, true, true, true);
        emit BoostsSet(destinationVaults, boosts);
        _hook.setBoosts(destinationVaults, boosts);
    }
}

contract Execute is PointsHookTests {
    function test_AppliesBoostToBaseApr() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](2);
        uint256[] memory boosts = new uint256[](2);

        destinationVaults[0] = address(1);
        destinationVaults[1] = address(2);
        boosts[0] = _hook.maxBoost();
        boosts[1] = 1;

        _hook.setBoosts(destinationVaults, boosts);

        IStrategy.SummaryStats memory stats;
        stats.baseApr = 1;

        stats = _hook.execute(stats, IAutopool(address(0)), address(1), 0, IAutopoolStrategy.RebalanceDirection.In, 0);

        assertEq(stats.baseApr, _hook.maxBoost() + 1, "newValue");
    }

    function test_ReturnsUnmodifiedWhenNoBoostSet() external {
        _mockIsPointsAdmin(address(this), true);
        _mockDestVaultRegVerifyIsRegistered(_destVaultRegistry, address(1), true);
        address[] memory destinationVaults = new address[](2);
        uint256[] memory boosts = new uint256[](2);

        destinationVaults[0] = address(1);
        destinationVaults[1] = address(2);
        boosts[0] = _hook.maxBoost();
        boosts[1] = 1;

        _hook.setBoosts(destinationVaults, boosts);

        IStrategy.SummaryStats memory stats;
        stats.baseApr = 1;

        stats = _hook.execute(stats, IAutopool(address(0)), address(3), 0, IAutopoolStrategy.RebalanceDirection.In, 0);

        assertEq(stats.baseApr, 1, "newValue");
    }
}
