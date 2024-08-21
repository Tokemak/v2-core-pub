// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { AutopoolDebt } from "src/vault/libs/AutopoolDebt.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IExtraRewarder } from "src/interfaces/rewarders/IExtraRewarder.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Lens is SystemComponent {
    /// =====================================================
    /// Structs
    /// =====================================================

    struct Autopool {
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
        IAutopool.VaultShutdownStatus shutdownStatus;
        address rewarder;
        address strategy;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 totalIdle;
        uint256 totalDebt;
        uint256 navPerShare;
    }

    struct AutopoolUserInfo {
        address autoPool;
        RewardToken[] rewardTokens;
        TokenAmount[] rewardTokenAmounts;
    }

    struct RewardToken {
        address tokenAddress;
    }

    struct TokenAmount {
        uint256 amount;
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

    struct Autopools {
        Autopool[] autoPools;
        DestinationVault[][] destinations;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Returns all Autopools currently registered in the system
    function getPools() external view returns (Autopool[] memory) {
        return _getPools();
    }

    /// @notice Returns all Autopools and their destinations
    /// @dev Makes no state changes. Not a view fn because of stats pricing
    function getPoolsAndDestinations() public returns (Autopools memory retValues) {
        retValues.autoPools = _getPools();
        retValues.destinations = new DestinationVault[][](retValues.autoPools.length);

        for (uint256 i = 0; i < retValues.autoPools.length; ++i) {
            retValues.destinations[i] = _getDestinations(retValues.autoPools[i].poolAddress);
        }
    }

    /// @notice Get the fee settings for an Autopool
    /// @dev Structure of this return struct has been updated a few times and will fail on the decode. This is paired
    /// with the _fillInFeeSettings call to ensure the failure doesn't bubble up
    /// @param poolAddress Address of the Autopool to query
    function proxyGetFeeSettings(address poolAddress) public view returns (IAutopool.AutopoolFeeSettings memory) {
        return IAutopool(poolAddress).getFeeSettings();
    }

    /// @notice Get the reward info for a user
    /// @param wallet Address of the wallet to query
    /// @return userInfo Array of AutopoolUserInfo structs containing reward tokens and amounts for each Autopool
    function getUserRewardInfo(address wallet) public view returns (AutopoolUserInfo[] memory userInfo) {
        Autopool[] memory autoPools = _getPools();
        uint256 nAutoPools = autoPools.length;
        userInfo = new AutopoolUserInfo[](nAutoPools);

        // Collect all reward tokens and amounts for each Autopool
        for (uint256 i = 0; i < nAutoPools; i++) {
            RewardToken[] memory rewardTokens = new RewardToken[](0);
            uint256 rewardTokenCount = 0;
            TokenAmount[] memory earnedAmounts = new TokenAmount[](0);
            uint256 earnedAmountCount = 0;

            // Add the Main Rewarder token and amount
            IMainRewarder mainRewarder = IMainRewarder(autoPools[i].rewarder);
            rewardTokens[rewardTokenCount] = RewardToken({ tokenAddress: mainRewarder.rewardToken() });
            rewardTokenCount++;
            earnedAmounts[earnedAmountCount] = TokenAmount({ amount: mainRewarder.earned(wallet) });
            earnedAmountCount++;

            // Add the Extra Rewarder tokens and amounts
            for (uint256 k = 0; k < mainRewarder.extraRewardsLength(); k++) {
                IExtraRewarder extraRewarder = IExtraRewarder(mainRewarder.getExtraRewarder(k));
                rewardTokens[rewardTokenCount] = RewardToken({ tokenAddress: extraRewarder.rewardToken() });
                rewardTokenCount++;
                earnedAmounts[earnedAmountCount] = TokenAmount({ amount: extraRewarder.earned(wallet) });
                earnedAmountCount++;
            }

            // Store the collected reward tokens and amounts for the Autopool
            userInfo[i] = AutopoolUserInfo({
                autoPool: autoPools[i].poolAddress,
                rewardTokens: rewardTokens,
                rewardTokenAmounts: earnedAmounts
            });
        }
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    /// @dev Returns Autopool information for those currently registered in the system
    function _getPools() private view returns (Autopool[] memory autoPools) {
        address[] memory autoPoolAddresses = systemRegistry.autoPoolRegistry().listVaults();
        autoPools = new Autopool[](autoPoolAddresses.length);

        for (uint256 i = 0; i < autoPoolAddresses.length; ++i) {
            address poolAddress = autoPoolAddresses[i];
            IAutopool vault = IAutopool(poolAddress);
            autoPools[i] = Autopool({
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
                strategy: address(vault.autoPoolStrategy()),
                totalSupply: vault.totalSupply(),
                totalAssets: vault.totalAssets(),
                totalIdle: vault.getAssetBreakdown().totalIdle,
                totalDebt: vault.getAssetBreakdown().totalDebt,
                navPerShare: vault.convertToAssets(10 ** vault.decimals())
            });
            _fillInFeeSettings(autoPools[i]);
        }
    }

    /// @dev Sets the fee settings with a call that loops back to this contract to ensure the struct can be decoded
    /// @param pool Autopool to fill in fees far
    function _fillInFeeSettings(Autopool memory pool) private view {
        try Lens(address(this)).proxyGetFeeSettings(pool.poolAddress) returns (
            IAutopool.AutopoolFeeSettings memory settings
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

    /// @dev Returns destination information for those currently related to the Autopool
    /// @param autoPool Autopool to query destinations for
    function _getDestinations(address autoPool) private returns (DestinationVault[] memory destinations) {
        address[] memory poolDestinations = IAutopool(autoPool).getDestinations();
        address[] memory poolQueuedDestRemovals = IAutopool(autoPool).getRemovalQueue();
        destinations = new DestinationVault[](poolDestinations.length + poolQueuedDestRemovals.length);

        for (uint256 i = 0; i < destinations.length; ++i) {
            address destinationAddress =
                i < poolDestinations.length ? poolDestinations[i] : poolQueuedDestRemovals[i - poolDestinations.length];
            (IDexLSTStats.DexLSTStatsData memory currentStats, bool statsIncomplete) =
                _safeDestinationGetStats(destinationAddress);
            address[] memory destinationTokens = IDestinationVault(destinationAddress).underlyingTokens();
            AutopoolDebt.DestinationInfo memory vaultDestInfo =
                IAutopool(autoPool).getDestinationInfo(destinationAddress);
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
