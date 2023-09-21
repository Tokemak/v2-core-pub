//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AccessControl } from "openzeppelin-contracts/access/AccessControl.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import { SecurityBase } from "src/security/SecurityBase.sol";
import { Roles } from "src/libs/Roles.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";

import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract LMPVaultRegistry is SystemComponent, ILMPVaultRegistry, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _vaults;
    EnumerableSet.AddressSet private _assets;

    // registry of vaults for a given asset
    mapping(address => EnumerableSet.AddressSet) private _vaultsByAsset;
    // registry of vaults for a given type
    mapping(bytes32 => EnumerableSet.AddressSet) private _vaultsByType;

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    modifier onlyUpdater() {
        if (!_hasRole(Roles.REGISTRY_UPDATER, msg.sender)) revert Errors.AccessDenied();
        _;
    }

    ///////////////////////////////////////////////////////////////////
    //
    //                        Update Methods
    //
    ///////////////////////////////////////////////////////////////////

    function addVault(address vaultAddress) external onlyUpdater {
        Errors.verifyNotZero(vaultAddress, "vaultAddress");

        ILMPVault vault = ILMPVault(vaultAddress);

        address asset = vault.asset();
        bytes32 vaultType = vault.vaultType();

        if (!_vaults.add(vaultAddress)) revert VaultAlreadyExists(vaultAddress);
        //slither-disable-next-line unused-return
        if (!_assets.contains(asset)) _assets.add(asset);

        if (!_vaultsByAsset[asset].add(vaultAddress)) revert VaultAlreadyExists(vaultAddress);
        if (!_vaultsByType[vaultType].add(vaultAddress)) revert VaultAlreadyExists(vaultAddress);

        emit VaultAdded(asset, vaultAddress);
    }

    function removeVault(address vaultAddress) external onlyUpdater {
        Errors.verifyNotZero(vaultAddress, "vaultAddress");

        // remove from vaults list
        if (!_vaults.remove(vaultAddress)) revert VaultNotFound(vaultAddress);

        ILMPVault vault = ILMPVault(vaultAddress);
        address asset = vault.asset();
        bytes32 vaultType = vault.vaultType();

        // remove from assets list if this was the last vault for that asset
        if (_vaultsByAsset[asset].length() == 1) {
            //slither-disable-next-line unused-return
            _assets.remove(asset);
        }

        // remove from vaultsByAsset mapping
        if (!_vaultsByAsset[asset].remove(vaultAddress)) revert VaultNotFound(vaultAddress);

        // remove from vaultsByType mapping
        if (!_vaultsByType[vaultType].remove(vaultAddress)) revert VaultNotFound(vaultAddress);

        emit VaultRemoved(asset, vaultAddress);
    }

    ///////////////////////////////////////////////////////////////////
    //
    //                        Enumeration Methods
    //
    ///////////////////////////////////////////////////////////////////

    function isVault(address vaultAddress) external view override returns (bool) {
        return _vaults.contains(vaultAddress);
    }

    function listVaults() external view returns (address[] memory) {
        return _vaults.values();
    }

    function listVaultsForAsset(address asset) external view returns (address[] memory) {
        return _vaultsByAsset[asset].values();
    }

    function listVaultsForType(bytes32 _vaultType) external view returns (address[] memory) {
        return _vaultsByType[_vaultType].values();
    }
}
