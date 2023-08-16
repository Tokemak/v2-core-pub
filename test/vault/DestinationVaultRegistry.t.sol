// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Errors } from "src/utils/Errors.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";

contract DestinationVaultRegistryBaseTests is Test {
    address private testUser2;
    address private factory;

    uint256 private destinationVaultCounter = 100_000;
    SystemRegistry private systemRegistry;
    IAccessController private accessController;
    DestinationVaultRegistry private registry;

    event FactorySet(address newFactory);
    event DestinationVaultRegistered(address vaultAddress, address caller);

    function setUp() public {
        testUser2 = vm.addr(2);
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        registry = new DestinationVaultRegistry(systemRegistry);
        factory = generateFactory(systemRegistry);
        registry.setVaultFactory(factory);
    }

    function testEnsuresSystemRegistryIsValid() public {
        vm.expectRevert();
        new DestinationVaultRegistry(ISystemRegistry(address(0)));
    }

    function testOnlyFactoryCanRegister() public {
        address newVault = generateDestinationVault(systemRegistry);

        // Run as not an owner and ensure it reverts
        vm.startPrank(testUser2);
        vm.expectRevert(abi.encodeWithSelector(DestinationVaultRegistry.OnlyFactory.selector));
        registry.register(newVault);
        vm.stopPrank();

        // Run as an owner and ensure it doesn't revert
        vm.startPrank(factory);
        registry.register(newVault);
        vm.stopPrank();
    }

    function testVaultCanOnlyBeRegisteredOnce() public {
        address newVault = generateDestinationVault(systemRegistry);
        vm.startPrank(factory);

        registry.register(newVault);
        vm.expectRevert(abi.encodeWithSelector(DestinationVaultRegistry.AlreadyRegistered.selector, newVault));
        registry.register(newVault);
        vm.stopPrank();
    }

    function testZeroAddressVaultCantBeRegistered() public {
        vm.startPrank(factory);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newDestinationVault"));
        registry.register(address(0));
        vm.stopPrank();
    }

    function testVaultRegistrationEmitsEvent() public {
        address newVault = generateDestinationVault(systemRegistry);
        vm.startPrank(factory);

        vm.expectEmit(true, true, true, true);
        emit DestinationVaultRegistered(newVault, factory);
        registry.register(newVault);
        vm.stopPrank();
    }

    function testVaultCorrectlyRegistersView() public {
        address newVault = generateDestinationVault(systemRegistry);
        address xVault = generateDestinationVault(systemRegistry);
        vm.startPrank(factory);
        registry.register(newVault);
        vm.stopPrank();

        bool isRegistered = registry.isRegistered(newVault);
        bool notRegistered = registry.isRegistered(xVault);

        assertEq(isRegistered, true, "isRegistered");
        assertEq(notRegistered, false, "notRegistered");
    }

    function testListValuesReturnsAllValues() public {
        address[] memory vaults = registry.listVaults();
        assertEq(vaults.length, 0);

        address newVault = generateDestinationVault(systemRegistry);
        address newVault2 = generateDestinationVault(systemRegistry);
        vm.startPrank(factory);
        registry.register(newVault);
        registry.register(newVault2);
        vm.stopPrank();

        vaults = registry.listVaults();

        assertEq(vaults.length, 2);
        assertEq(vaults[0], address(newVault));
        assertEq(vaults[1], address(newVault2));
    }

    function testOnlyOwnerCanSetFactory() public {
        vm.startPrank(factory);
        address newFactory = generateFactory(new SystemRegistry(TOKE_MAINNET, WETH_MAINNET));
        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        registry.setVaultFactory(newFactory);
        vm.stopPrank();
    }

    function testFactoryCantBeSetToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newAddress"));
        registry.setVaultFactory(address(0));
    }

    function testSetFactoryEmitsEvent() public {
        address newFactory = generateFactory(systemRegistry);
        vm.expectEmit(true, true, true, true);
        emit FactorySet(newFactory);
        registry.setVaultFactory(newFactory);
    }

    function testSetFactoryValidatesSystemMatch() public {
        SystemRegistry newRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        address newFactory = generateFactory(newRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(DestinationVaultRegistry.SystemMismatch.selector, systemRegistry, newRegistry)
        );
        registry.setVaultFactory(newFactory);
    }

    function generateFactory(ISystemRegistry sysRegistry) internal returns (address) {
        address f = vm.addr(7);
        vm.mockCall(f, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(sysRegistry));
        return f;
    }

    function generateDestinationVault(ISystemRegistry sysRegistry) internal returns (address) {
        destinationVaultCounter++;
        address v = vm.addr(destinationVaultCounter);
        vm.mockCall(v, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(sysRegistry));
        return v;
    }
}
