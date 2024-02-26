// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";

/// @notice Queries the system to get the Vaults data in convenient representable way
interface ILens {
    struct LMPVault {
        address vaultAddress;
        string name;
        string symbol;
        bytes32 vaultType;
        address baseAsset;
        uint256 streamingFeeBps;
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

    struct DestinationStats {
        uint256 lastSnapshotTimestamp;
        uint256 feeApr;
        uint256[] reservesInEth;
        ILSTStats.LSTStatsData[] lstStatsData;
        IDexLSTStats.StakingIncentiveStats stakingIncentiveStats;
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
     * @return tokens a matrix of ERC-20s wrapped to `UnderlyingToken`
     */
    function getVaultDestinationTokens()
        external
        view
        returns (address[] memory destinationVaults, ILens.UnderlyingToken[][] memory tokens);

    /**
     * @notice Gets a combination current stats data and corresponding DestinationVault addresses
     * @return destinationVaults an array of addresses for corresponding tokens
     * @return stats an array containing `LSTStatsData`, `StakingIncentiveStats`, and other data
     */
    function getVaultDestinationStats()
        external
        returns (address[] memory destinationVaults, ILens.DestinationStats[] memory stats);
}
