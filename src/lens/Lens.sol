// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { ILens } from "src/interfaces/lens/ILens.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

contract Lens is ILens, SystemComponent {
    ILMPVaultRegistry public immutable lmpRegistry;

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) {
        ILMPVaultRegistry _lmpRegistry = _systemRegistry.lmpVaultRegistry();

        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_lmpRegistry), "lmpRegistry");

        lmpRegistry = _lmpRegistry;
    }

    /// @inheritdoc ILens
    function getVaults()
        external
        view
        override
        returns (ILens.LMPVault[] memory lmpVaults, address[] memory vaultAddresses)
    {
        address[] memory lmpAddresses = lmpRegistry.listVaults();
        lmpVaults = new ILens.LMPVault[](lmpAddresses.length);
        vaultAddresses = new address[](lmpAddresses.length);

        for (uint256 i = 0; i < lmpAddresses.length; ++i) {
            address vaultAddress = lmpAddresses[i];
            ILMPVault vault = ILMPVault(vaultAddress);
            lmpVaults[i] = ILens.LMPVault(vault.name(), vault.symbol());
            vaultAddresses[i] = vaultAddress;
        }
    }

    /// @inheritdoc ILens
    function getDestinations(address lmpVault)
        external
        view
        override
        returns (ILens.DestinationVault[] memory destinations, address[] memory destinationAddresses)
    {
        address[] memory vaults = ILMPVault(lmpVault).getDestinations();
        destinations = new ILens.DestinationVault[](vaults.length);
        destinationAddresses = new address[](vaults.length);

        for (uint256 i = 0; i < vaults.length; ++i) {
            address vaultAddress = vaults[i];
            IDestinationVault destination = IDestinationVault(vaultAddress);
            destinations[i] = ILens.DestinationVault(destination.exchangeName());
            destinationAddresses[i] = vaultAddress;
        }
    }

    /// @inheritdoc ILens
    function getUnderlyingTokens(address destination)
        external
        view
        override
        returns (ILens.UnderlyingToken[] memory underlyingTokens)
    {
        address[] memory tokens = IDestinationVault(destination).underlyingTokens();
        underlyingTokens = new ILens.UnderlyingToken[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            address tokenAddress = tokens[i];
            underlyingTokens[i] = ILens.UnderlyingToken(tokenAddress, IERC20Metadata(tokenAddress).symbol());
        }
    }
}
