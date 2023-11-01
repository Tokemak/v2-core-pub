// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count

import { BaseTest } from "test/BaseTest.t.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { ILMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";

contract LMPVaultRegistryTest is BaseTest {
    LMPVault internal vault;

    event VaultAdded(address indexed asset, address indexed vault);
    event VaultRemoved(address indexed asset, address indexed vault);

    function setUp() public virtual override {
        super._setUp(false);

        lmpVaultRegistry = new LMPVaultRegistry(systemRegistry);
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));

        bytes memory initData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_001) }));

        vault = LMPVault(
            lmpVaultFactory.createVault(type(uint112).max, type(uint112).max, "x", "y", keccak256("v8"), initData)
        );
    }

    function _contains(address[] memory arr, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] == value) {
                return true;
            }
        }
        return false;
    }
}

contract AddVault is LMPVaultRegistryTest {
    function test_AddVault() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        lmpVaultRegistry.addVault(address(vault));

        assert(lmpVaultRegistry.isVault(address(vault)));
        assert(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(lmpVaultRegistry.listVaults(), address(vault)));
    }

    function test_AddMultipleVaults() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));
        lmpVaultRegistry.addVault(address(vault));

        bytes memory initData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_002) }));

        LMPVault anotherVault = LMPVault(
            lmpVaultFactory.createVault(type(uint112).max, type(uint112).max, "x", "y", keccak256("v9"), initData)
        );

        vm.expectEmit(true, true, false, true);
        emit VaultAdded(anotherVault.asset(), address(anotherVault));
        lmpVaultRegistry.addVault(address(anotherVault));

        assert(lmpVaultRegistry.isVault(address(vault)));
        assert(lmpVaultRegistry.isVault(address(anotherVault)));
        assertEq(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length, 2);
        assertEq(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length, 2);
        assert(_contains(lmpVaultRegistry.listVaults(), address(vault)));
        assert(_contains(lmpVaultRegistry.listVaults(), address(anotherVault)));
    }

    // Covering https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/068-M/068.md
    function test_AddVaultAfterRemove() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        lmpVaultRegistry.addVault(address(vault));

        assert(lmpVaultRegistry.isVault(address(vault)));
        assert(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(lmpVaultRegistry.listVaults(), address(vault)));

        vm.expectEmit(true, true, false, true);
        emit VaultRemoved(vault.asset(), address(vault));
        lmpVaultRegistry.removeVault(address(vault));

        assertFalse(lmpVaultRegistry.isVault(address(vault)));
        assertEq(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length, 0);
        assertEq(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length, 0);
        assertFalse(_contains(lmpVaultRegistry.listVaults(), address(vault)));

        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        lmpVaultRegistry.addVault(address(vault));

        assert(lmpVaultRegistry.isVault(address(vault)));
        assert(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(lmpVaultRegistry.listVaults(), address(vault)));
    }

    function test_RevertIf_AddingVaultWithNoPermission() public {
        accessController.revokeRole(Roles.REGISTRY_UPDATER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        lmpVaultRegistry.addVault(address(vault));
    }

    function test_RevertIf_AddingExistingVault() public {
        lmpVaultRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRegistry.VaultAlreadyExists.selector, address(vault)));
        lmpVaultRegistry.addVault(address(vault));
    }

    function test_RevertIf_AddingZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vaultAddress"));
        lmpVaultRegistry.addVault(address(0));
    }
}

contract RemoveVault is LMPVaultRegistryTest {
    function test_RemoveVault() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        lmpVaultRegistry.addVault(address(vault));

        vm.expectEmit(true, true, false, true);
        emit VaultRemoved(vault.asset(), address(vault));
        lmpVaultRegistry.removeVault(address(vault));

        assertFalse(lmpVaultRegistry.isVault(address(vault)));
        assertEq(lmpVaultRegistry.listVaultsForAsset(vault.asset()).length, 0);
        assertEq(lmpVaultRegistry.listVaultsForType(VaultTypes.LST).length, 0);
        assertFalse(_contains(lmpVaultRegistry.listVaults(), address(vault)));
    }

    function test_RevertIf_RemovingVaultWithNoPermission() public {
        lmpVaultRegistry.addVault(address(vault));

        accessController.revokeRole(Roles.REGISTRY_UPDATER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        lmpVaultRegistry.removeVault(address(vault));
    }

    function test_RevertIf_RemovingZeroAddress() public {
        lmpVaultRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vaultAddress"));
        lmpVaultRegistry.removeVault(address(0));
    }

    function test_RevertIf_RemovingNonExistingVault() public {
        lmpVaultRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRegistry.VaultNotFound.selector, address(123)));
        lmpVaultRegistry.removeVault(address(123));
    }
}
