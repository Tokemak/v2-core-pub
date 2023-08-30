// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @notice Queries the system to get the Vaults data in convenient representable way
interface ILens {
    struct LMPVault {
        address vaultAddress;
        string name;
        string symbol;
        bytes32 vaultType;
        address baseAsset;
        uint256 performanceFeeBps;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 totalIdle;
        uint256 totalDebt;
    }

    struct DestinationVault {
        address vaultAddress;
        string exchangeName;
    }

    struct UnderlyingToken {
        address tokenAddress;
        string symbol;
    }

    /**
     * @notice Gets LMPVaults
     * @return lmpVaults an array of `LMPVault` data
     */
    function getVaults() external view returns (ILens.LMPVault[] memory lmpVaults);

    /**
     * @notice Gets DestinationVaults and corresponding LMPVault addresses
     * @return lmpVaults an array of addresses for corresponding destinations
     * @return destinations a matrix of `DestinationVault` data
     */
    function getVaultDestinations()
        external
        view
        returns (address[] memory lmpVaults, ILens.DestinationVault[][] memory destinations);

    /**
     * @notice Gets UnderlyingTokens and corresponding DestinationVault addresses
     * @return destinationVaults an array of addresses for corresponding tokens
     * @return tokens a matrix of of ERC-20s wrapped to `UnderlyingToken`
     */
    function getVaultDestinationTokens()
        external
        view
        returns (address[] memory destinationVaults, ILens.UnderlyingToken[][] memory tokens);
}
