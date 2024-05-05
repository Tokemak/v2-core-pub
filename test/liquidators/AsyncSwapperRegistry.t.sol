// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract AsyncSwapperRegistryTest is Test {
    AsyncSwapperRegistry public registry;

    function setUp() public {
        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        registry = new AsyncSwapperRegistry(systemRegistry);

        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
    }

    function test_Revert_register_IfAccessDenied() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(address(0));
        registry.register(address(0));
    }

    function test_Revert_unregister_IfAccessDenied() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(address(0));
        registry.unregister(address(0));
    }

    function test_Revert_register_IfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swapperAddress"));
        registry.register(address(0));
    }

    function test_Revert_unregister_IfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swapperAddress"));
        registry.unregister(address(0));
    }

    function test_Revert_register_IfSwapperAlreadyExists() public {
        registry.register(address(1));

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        registry.register(address(1));
    }

    function test_Revert_unregister_IfSwapperNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        registry.unregister(address(1));
    }

    function test_Revert_verifyIsRegistered_IfSwapperNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));
        registry.verifyIsRegistered(address(1));
    }

    function test_register_Successful() public {
        registry.register(address(1));
        bool exists = registry.isRegistered(address(1));
        assertTrue(exists);
    }

    function test_unregister_Successful() public {
        registry.register(address(1));
        bool exists = registry.isRegistered(address(1));
        assertTrue(exists);

        registry.unregister(address(1));
        exists = registry.isRegistered(address(1));
        assertFalse(exists);
    }

    function test_list_Successful() public {
        registry.register(address(1));
        registry.register(address(2));
        registry.register(address(3));
        address[] memory list = registry.list();
        assertEq(list.length, 3);
    }
}
