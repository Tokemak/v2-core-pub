// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Lens is SystemComponent {
    /// =====================================================
    /// Structs
    /// =====================================================

    struct AutoPool {
        address poolAddress;
        string name;
        string symbol;
        bytes32 vaultType;
        address baseAsset;
        uint256 streamingFeeBps;
        uint256 periodicFeeBps;
        bool feeHighMarkEnabled;
        bool feeSettingsIncomplete;
        bool isShutdown;
        ILMPVault.VaultShutdownStatus shutdownStatus;
        address rewarder;
        address strategy;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 totalIdle;
        uint256 totalDebt;
        uint256 navPerShare;
    }

    struct RewardToken {
        address tokenAddress;
    }

    struct UnderlyingTokenValueHeld {
        uint256 valueHeldInEth;
    }

    struct UnderlyingTokenAddress {
        address tokenAddress;
    }

    struct UnderlyingTokenSymbol {
        string symbol;
    }

    struct DestinationVault {
        address vaultAddress;
        string exchangeName;
        uint256 totalSupply;
        uint256 lastSnapshotTimestamp;
        uint256 feeApr;
        uint256 lastDebtReportTime;
        uint256 minDebtValue;
        uint256 maxDebtValue;
        uint256 debtValueHeldByVault;
        bool queuedForRemoval;
        bool statsIncomplete;
        bool isShutdown;
        IDestinationVault.VaultShutdownStatus shutdownStatus;
        uint256 autoPoolOwnsShares;
        uint256 actualLPTotalSupply;
        address dexPool;
        address lpTokenAddress;
        string lpTokenSymbol;
        string lpTokenName;
        uint256 statsSafeLPTotalSupply;
        uint8 statsIncentiveCredits;
        RewardToken[] rewardsTokens;
        UnderlyingTokenAddress[] underlyingTokens;
        UnderlyingTokenSymbol[] underlyingTokenSymbols;
        ILSTStats.LSTStatsData[] lstStatsData;
        UnderlyingTokenValueHeld[] underlyingTokenValueHeld;
        uint256[] reservesInEth;
        uint40[] statsPeriodFinishForRewards;
        uint256[] statsAnnualizedRewardAmounts;
    }

    struct AutoPools {
        AutoPool[] autoPools;
        DestinationVault[][] destinations;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Returns all AutoPools currently registered in the system
    function getPools() external view returns (AutoPool[] memory) {
        return _getPools();
    }

    /// @notice Returns all AutoPools and their destinations
    /// @dev Makes no state changes. Not a view fn because of stats pricing
    function getPoolsAndDestinations() external returns (AutoPools memory retValues) {
        retValues.autoPools = _getPools();
        retValues.destinations = new DestinationVault[][](retValues.autoPools.length);

        for (uint256 i = 0; i < retValues.autoPools.length; ++i) {
            retValues.destinations[i] = _getDestinations(retValues.autoPools[i].poolAddress);
        }
    }

    /// @notice Get the fee settings for an AutoPool
    /// @dev Structure of this return struct has been updated a few times and will fail on the decode. This is paired
    /// with the _fillInFeeSettings call to ensure the failure doesn't bubble up
    /// @param poolAddress Address of the AutoPool to query
    function proxyGetFeeSettings(address poolAddress) public view returns (ILMPVault.AutoPoolFeeSettings memory) {
        return ILMPVault(poolAddress).getFeeSettings();
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    /// @dev Returns AutoPool information for those currently registered in the system
    function _getPools() private view returns (AutoPool[] memory lmpVaults) {
        address[] memory lmpAddresses = systemRegistry.lmpVaultRegistry().listVaults();
        lmpVaults = new AutoPool[](lmpAddresses.length);

        for (uint256 i = 0; i < lmpAddresses.length; ++i) {
            address poolAddress = lmpAddresses[i];
            ILMPVault vault = ILMPVault(poolAddress);
            lmpVaults[i] = AutoPool({
                poolAddress: poolAddress,
                name: vault.name(),
                symbol: vault.symbol(),
                vaultType: vault.vaultType(),
                baseAsset: vault.asset(),
                streamingFeeBps: 0,
                periodicFeeBps: 0,
                feeHighMarkEnabled: false,
                feeSettingsIncomplete: true,
                isShutdown: vault.isShutdown(),
                shutdownStatus: vault.shutdownStatus(),
                rewarder: address(vault.rewarder()),
                strategy: address(vault.lmpStrategy()),
                totalSupply: vault.totalSupply(),
                totalAssets: vault.totalAssets(),
                totalIdle: vault.getAssetBreakdown().totalIdle,
                totalDebt: vault.getAssetBreakdown().totalDebt,
                navPerShare: vault.convertToAssets(10 ** vault.decimals())
            });
            _fillInFeeSettings(lmpVaults[i]);
        }
    }

    /// @dev Sets the fee settings with a call that loops back to this contract to ensure the struct can be decoded
    /// @param pool AutoPool to fill in fees far
    function _fillInFeeSettings(AutoPool memory pool) private view {
        try Lens(address(this)).proxyGetFeeSettings(pool.poolAddress) returns (
            ILMPVault.AutoPoolFeeSettings memory settings
        ) {
            pool.streamingFeeBps = settings.streamingFeeBps;
            pool.periodicFeeBps = settings.periodicFeeBps;
            pool.feeHighMarkEnabled = settings.rebalanceFeeHighWaterMarkEnabled;
            pool.feeSettingsIncomplete = true;
        } catch { }
    }

    /// @dev Returns a destinations current stats. Can fail when prices are stale we capture that here
    /// @param destinationAddress Address of the destination to query stats for
    function _safeDestinationGetStats(address destinationAddress)
        private
        returns (IDexLSTStats.DexLSTStatsData memory currentStats, bool incomplete)
    {
        try IDestinationVault(destinationAddress).getStats().current() returns (
            IDexLSTStats.DexLSTStatsData memory queriedStats
        ) {
            currentStats = queriedStats;
        } catch {
            incomplete = true;
        }
    }

    /// @dev Returns destination information for those currently related to the AutoPool
    /// @param autoPool AutoPool to query destinations for
    function _getDestinations(address autoPool) private returns (DestinationVault[] memory destinations) {
        address[] memory poolDestinations = ILMPVault(autoPool).getDestinations();
        address[] memory poolQueuedDestRemovals = ILMPVault(autoPool).getRemovalQueue();
        destinations = new DestinationVault[](poolDestinations.length + poolQueuedDestRemovals.length);

        for (uint256 i = 0; i < destinations.length; ++i) {
            address destinationAddress =
                i < poolDestinations.length ? poolDestinations[i] : poolQueuedDestRemovals[i - poolDestinations.length];
            (IDexLSTStats.DexLSTStatsData memory currentStats, bool statsIncomplete) =
                _safeDestinationGetStats(destinationAddress);
            address[] memory destinationTokens = IDestinationVault(destinationAddress).underlyingTokens();
            LMPDebt.DestinationInfo memory vaultDestInfo = ILMPVault(autoPool).getDestinationInfo(destinationAddress);
            uint256 vaultBalOfDest = IDestinationVault(destinationAddress).balanceOf(autoPool);

            destinations[i] = DestinationVault({
                vaultAddress: destinationAddress,
                exchangeName: IDestinationVault(destinationAddress).exchangeName(),
                totalSupply: IDestinationVault(destinationAddress).totalSupply(),
                lastSnapshotTimestamp: currentStats.lastSnapshotTimestamp,
                feeApr: currentStats.feeApr,
                lastDebtReportTime: vaultDestInfo.lastReport,
                minDebtValue: vaultDestInfo.ownedShares > 0
                    ? vaultDestInfo.cachedMinDebtValue * vaultBalOfDest / vaultDestInfo.ownedShares
                    : 0,
                maxDebtValue: vaultDestInfo.ownedShares > 0
                    ? vaultDestInfo.cachedMaxDebtValue * vaultBalOfDest / vaultDestInfo.ownedShares
                    : 0,
                debtValueHeldByVault: (
                    vaultDestInfo.ownedShares > 0
                        ? (vaultDestInfo.cachedMinDebtValue * vaultBalOfDest / vaultDestInfo.ownedShares)
                            + (vaultDestInfo.cachedMaxDebtValue * vaultBalOfDest / vaultDestInfo.ownedShares)
                        : 0
                    ) / 2,
                queuedForRemoval: i >= poolDestinations.length,
                isShutdown: IDestinationVault(destinationAddress).isShutdown(),
                shutdownStatus: IDestinationVault(destinationAddress).shutdownStatus(),
                statsIncomplete: statsIncomplete,
                autoPoolOwnsShares: vaultBalOfDest,
                actualLPTotalSupply: IERC20Metadata(IDestinationVault(destinationAddress).underlying()).totalSupply(),
                dexPool: IDestinationVault(destinationAddress).getPool(),
                lpTokenAddress: IDestinationVault(destinationAddress).underlying(),
                lpTokenSymbol: IERC20Metadata(IDestinationVault(destinationAddress).underlying()).symbol(),
                lpTokenName: IERC20Metadata(IDestinationVault(destinationAddress).underlying()).name(),
                statsSafeLPTotalSupply: currentStats.stakingIncentiveStats.safeTotalSupply,
                statsIncentiveCredits: currentStats.stakingIncentiveStats.incentiveCredits,
                reservesInEth: currentStats.reservesInEth,
                statsPeriodFinishForRewards: currentStats.stakingIncentiveStats.periodFinishForRewards,
                statsAnnualizedRewardAmounts: currentStats.stakingIncentiveStats.annualizedRewardAmounts,
                rewardsTokens: new RewardToken[](currentStats.stakingIncentiveStats.rewardTokens.length),
                underlyingTokens: new UnderlyingTokenAddress[](destinationTokens.length),
                underlyingTokenSymbols: new UnderlyingTokenSymbol[](destinationTokens.length),
                lstStatsData: currentStats.lstStatsData,
                underlyingTokenValueHeld: new UnderlyingTokenValueHeld[](destinationTokens.length)
            });

            for (uint256 r = 0; r < currentStats.stakingIncentiveStats.rewardTokens.length; ++r) {
                destinations[i].rewardsTokens[r] =
                    RewardToken({ tokenAddress: currentStats.stakingIncentiveStats.rewardTokens[r] });
            }

            for (uint256 t = 0; t < destinationTokens.length; ++t) {
                address tokenAddress = destinationTokens[t];
                destinations[i].underlyingTokens[t] = UnderlyingTokenAddress({ tokenAddress: tokenAddress });
                destinations[i].underlyingTokenSymbols[t] =
                    UnderlyingTokenSymbol({ symbol: IERC20Metadata(tokenAddress).symbol() });

                if (destinationTokens.length == destinations[i].reservesInEth.length) {
                    destinations[i].underlyingTokenValueHeld[t] = UnderlyingTokenValueHeld({
                        valueHeldInEth: destinations[i].reservesInEth[t] * destinations[i].autoPoolOwnsShares
                            / destinations[i].actualLPTotalSupply
                    });
                }
            }
        }
    }
}
