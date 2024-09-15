// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count,one-contract-per-file

import { BaseTest } from "test/BaseTest.t.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { IAutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";
import { AutopoolETHStrategyTestHelpers as stratHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";

contract AutopoolRegistryTest is BaseTest {
    AutopoolETH internal vault;

    event VaultAdded(address indexed asset, address indexed vault);
    event VaultRemoved(address indexed asset, address indexed vault);

    function setUp() public virtual override {
        vm.warp(1000 days);

        super._setUp(false);

        autoPoolRegistry = new AutopoolRegistry(systemRegistry);
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_FACTORY_MANAGER, address(this));

        bytes memory initData = abi.encode("");

        AutopoolETHStrategy stratTemplate = new AutopoolETHStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        vault = AutopoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256("v8"), initData
            )
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

contract AddVault is AutopoolRegistryTest {
    function test_AddVault() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        autoPoolRegistry.addVault(address(vault));

        assert(autoPoolRegistry.isVault(address(vault)));
        assert(autoPoolRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(autoPoolRegistry.listVaults(), address(vault)));
    }

    function test_AddMultipleVaults() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));
        autoPoolRegistry.addVault(address(vault));

        bytes memory initData = abi.encode("");

        AutopoolETHStrategy stratTemplate = new AutopoolETHStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        AutopoolETH anotherVault = AutopoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256("v9"), initData
            )
        );

        vm.expectEmit(true, true, false, true);
        emit VaultAdded(anotherVault.asset(), address(anotherVault));
        autoPoolRegistry.addVault(address(anotherVault));

        assert(autoPoolRegistry.isVault(address(vault)));
        assert(autoPoolRegistry.isVault(address(anotherVault)));
        assertEq(autoPoolRegistry.listVaultsForAsset(vault.asset()).length, 2);
        assertEq(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length, 2);
        assert(_contains(autoPoolRegistry.listVaults(), address(vault)));
        assert(_contains(autoPoolRegistry.listVaults(), address(anotherVault)));
    }

    // Covering https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/068-M/068.md
    function test_AddVaultAfterRemove() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        autoPoolRegistry.addVault(address(vault));

        assert(autoPoolRegistry.isVault(address(vault)));
        assert(autoPoolRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(autoPoolRegistry.listVaults(), address(vault)));

        vm.expectEmit(true, true, false, true);
        emit VaultRemoved(vault.asset(), address(vault));
        autoPoolRegistry.removeVault(address(vault));

        assertFalse(autoPoolRegistry.isVault(address(vault)));
        assertEq(autoPoolRegistry.listVaultsForAsset(vault.asset()).length, 0);
        assertEq(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length, 0);
        assertFalse(_contains(autoPoolRegistry.listVaults(), address(vault)));

        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        autoPoolRegistry.addVault(address(vault));

        assert(autoPoolRegistry.isVault(address(vault)));
        assert(autoPoolRegistry.listVaultsForAsset(vault.asset()).length > 0);
        assert(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length > 0);
        assert(_contains(autoPoolRegistry.listVaults(), address(vault)));
    }

    function test_RevertIf_AddingVaultWithNoPermission() public {
        accessController.revokeRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        autoPoolRegistry.addVault(address(vault));
    }

    function test_RevertIf_AddingExistingVault() public {
        autoPoolRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(IAutopoolRegistry.VaultAlreadyExists.selector, address(vault)));
        autoPoolRegistry.addVault(address(vault));
    }

    function test_RevertIf_AddingZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vaultAddress"));
        autoPoolRegistry.addVault(address(0));
    }
}

contract RemoveVault is AutopoolRegistryTest {
    function test_RemoveVault() public {
        vm.expectEmit(true, true, false, true);
        emit VaultAdded(vault.asset(), address(vault));

        autoPoolRegistry.addVault(address(vault));

        vm.expectEmit(true, true, false, true);
        emit VaultRemoved(vault.asset(), address(vault));
        autoPoolRegistry.removeVault(address(vault));

        assertFalse(autoPoolRegistry.isVault(address(vault)));
        assertEq(autoPoolRegistry.listVaultsForAsset(vault.asset()).length, 0);
        assertEq(autoPoolRegistry.listVaultsForType(VaultTypes.LST).length, 0);
        assertFalse(_contains(autoPoolRegistry.listVaults(), address(vault)));
    }

    function test_RevertIf_RemovingVaultWithNoPermission() public {
        autoPoolRegistry.addVault(address(vault));

        accessController.revokeRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        autoPoolRegistry.removeVault(address(vault));
    }

    function test_RevertIf_RemovingZeroAddress() public {
        autoPoolRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vaultAddress"));
        autoPoolRegistry.removeVault(address(0));
    }

    function test_RevertIf_RemovingNonExistingVault() public {
        autoPoolRegistry.addVault(address(vault));

        vm.expectRevert(abi.encodeWithSelector(IAutopoolRegistry.VaultNotFound.selector, address(123)));
        autoPoolRegistry.removeVault(address(123));
    }
}
