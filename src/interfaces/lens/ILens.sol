// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @notice Queries the system to get the Vaults data in convenient representable way
interface ILens {
    struct LMPVault {
        string name;
        string symbol;
    }

    struct DestinationVault {
        string exchangeName;
    }

    struct UnderlyingToken {
        address tokenAddress;
        string symbol;
    }

    /**
     * @notice Gets LMPVault data
     * @return lmpVaults an array of `LMPVault`
     * @return vaultAddresses an array of addresses for corresponding vaults
     */
    function getVaults() external view returns (ILens.LMPVault[] memory lmpVaults, address[] memory vaultAddresses);

    /**
     * @notice Gets DestinationVaults from the given LMPVault
     * @param lmpVault address to query DestinationVaults from
     * @return destinations an array of `DestinationVault`
     * @return destinationAddresses an array of addresses for corresponding vaults
     */
    function getDestinations(address lmpVault)
        external
        view
        returns (ILens.DestinationVault[] memory destinations, address[] memory destinationAddresses);

    /**
     * @notice Gets UnderlyingTokens from the given DestinationVault
     * @param destination address to query UnderlyingTokens from
     * @return underlyingTokens an array of ERC-20s wrapped to `UnderlyingToken`
     */
    function getUnderlyingTokens(address destination)
        external
        view
        returns (ILens.UnderlyingToken[] memory underlyingTokens);
}
