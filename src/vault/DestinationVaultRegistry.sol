//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { AccessControl } from "openzeppelin-contracts/access/AccessControl.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IDestinationVaultFactory } from "src/interfaces/vault/IDestinationVaultFactory.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract DestinationVaultRegistry is SystemComponent, IDestinationVaultRegistry, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    IDestinationVaultFactory public factory;
    EnumerableSet.AddressSet private vaults;

    modifier onlyFactory() {
        if (msg.sender != address(factory)) {
            revert OnlyFactory();
        }
        _;
    }

    event FactorySet(address newFactory);
    event DestinationVaultRegistered(address vaultAddress, address caller);

    error OnlyFactory();
    error AlreadyRegistered(address vaultAddress);
    error SystemMismatch(address ours, address theirs);

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// @inheritdoc IDestinationVaultRegistry
    function isRegistered(address destinationVault) external view returns (bool) {
        return vaults.contains(destinationVault);
    }

    /// @inheritdoc IDestinationVaultRegistry
    function verifyIsRegistered(address destinationVault) external view override {
        if (!vaults.contains(destinationVault)) revert Errors.NotRegistered();
    }

    /// @inheritdoc IDestinationVaultRegistry
    function register(address newDestinationVault) external onlyFactory {
        Errors.verifyNotZero(newDestinationVault, "newDestinationVault");

        if (!vaults.add(newDestinationVault)) {
            revert AlreadyRegistered(newDestinationVault);
        }

        emit DestinationVaultRegistered(newDestinationVault, msg.sender);
    }

    /// @inheritdoc IDestinationVaultRegistry
    function listVaults() external view returns (address[] memory) {
        return vaults.values();
    }

    /// @notice Changes the factory that is allowed to register new vaults
    /// @dev Systems must match
    /// @param newAddress Address of the new factory
    function setVaultFactory(address newAddress) external onlyOwner {
        Errors.verifyNotZero(newAddress, "newAddress");

        factory = IDestinationVaultFactory(newAddress);

        emit FactorySet(newAddress);

        ISystemRegistry factorySystem = ISystemRegistry(factory.getSystemRegistry());

        if (factorySystem != systemRegistry) {
            revert SystemMismatch(address(systemRegistry), address(factorySystem));
        }
    }
}
