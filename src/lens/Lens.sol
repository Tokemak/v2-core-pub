// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { ILens } from "src/interfaces/lens/ILens.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract Lens is ILens, SystemComponent {
    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /// @inheritdoc ILens
    function getVaults() external view override returns (ILens.LMPVault[] memory lmpVaults) {
        address[] memory lmpAddresses = systemRegistry.lmpVaultRegistry().listVaults();
        lmpVaults = new ILens.LMPVault[](lmpAddresses.length);

        for (uint256 i = 0; i < lmpAddresses.length; ++i) {
            address vaultAddress = lmpAddresses[i];
            ILMPVault vault = ILMPVault(vaultAddress);
            lmpVaults[i] = ILens.LMPVault({
                vaultAddress: vaultAddress,
                name: vault.name(),
                symbol: vault.symbol(),
                vaultType: vault.vaultType(),
                baseAsset: vault.asset(),
                performanceFeeBps: vault.performanceFeeBps(),
                totalSupply: vault.totalSupply(),
                totalAssets: vault.totalAssets(),
                totalIdle: vault.totalIdle(),
                totalDebt: vault.totalDebt()
            });
        }
    }

    /// @inheritdoc ILens
    function getVaultDestinations()
        external
        view
        override
        returns (address[] memory lmpVaults, ILens.DestinationVault[][] memory destinations)
    {
        lmpVaults = systemRegistry.lmpVaultRegistry().listVaults();
        destinations = new ILens.DestinationVault[][](lmpVaults.length);

        for (uint256 i = 0; i < lmpVaults.length; ++i) {
            destinations[i] = _getDestinations(lmpVaults[i]);
        }
    }

    /// @inheritdoc ILens
    function getVaultDestinationTokens()
        external
        view
        override
        returns (address[] memory destinationVaults, ILens.UnderlyingToken[][] memory tokens)
    {
        destinationVaults = systemRegistry.destinationVaultRegistry().listVaults();
        tokens = new ILens.UnderlyingToken[][](destinationVaults.length);

        for (uint256 i = 0; i < destinationVaults.length; ++i) {
            tokens[i] = _getTokens(destinationVaults[i]);
        }
    }

    function _getDestinations(address lmpVault) private view returns (ILens.DestinationVault[] memory destinations) {
        address[] memory vaultDestinations = ILMPVault(lmpVault).getDestinations();
        destinations = new ILens.DestinationVault[](vaultDestinations.length);
        for (uint256 i = 0; i < vaultDestinations.length; ++i) {
            address destinationAddress = vaultDestinations[i];
            IDestinationVault destination = IDestinationVault(destinationAddress);
            destinations[i] = ILens.DestinationVault(destinationAddress, destination.exchangeName());
        }
    }

    function _getTokens(address destinationVault) private view returns (ILens.UnderlyingToken[] memory tokens) {
        address[] memory destinationTokens = IDestinationVault(destinationVault).underlyingTokens();
        tokens = new ILens.UnderlyingToken[](destinationTokens.length);
        for (uint256 i = 0; i < destinationTokens.length; ++i) {
            address tokenAddress = destinationTokens[i];
            tokens[i] = ILens.UnderlyingToken(tokenAddress, IERC20Metadata(tokenAddress).symbol());
        }
    }
}
