// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { AutoPoolToken } from "src/vault/libs/AutoPoolToken.sol";

library AutoPoolFees {
    using Math for uint256;
    using AutoPoolToken for AutoPoolToken.TokenData;

    /// @notice Profit denomination
    uint256 public constant MAX_BPS_PROFIT = 1_000_000_000;

    /// @notice 100% == 10000
    uint256 public constant FEE_DIVISOR = 10_000;

    /// @notice Time between periodic fee takes.  ~ half year.
    uint256 public constant PERIODIC_FEE_TAKE_TIMEFRAME = 182 days;

    /// @notice Max periodic fee, 10%.  100% = 10_000.
    uint256 public constant MAX_PERIODIC_FEE_BPS = 1000;

    /// @notice Time before a periodic fee is taken that the fee % can be changed.
    uint256 public constant PERIODIC_FEE_CHANGE_CUTOFF = 45 days;

    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 totalAssets);
    event PeriodicFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event PeriodicFeeSet(uint256 newFee);
    event PendingPeriodicFeeSet(uint256 pendingPeriodicFeeBps);
    event PeriodicFeeSinkSet(address newPeriodicFeeSink);
    event NextPeriodicFeeTakeSet(uint256 nextPeriodicFeeTake);
    event RebalanceFeeHighWaterMarkEnabledSet(bool enabled);
    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event NewTotalAssetsHighWatermark(uint256 assets, uint256 timestamp);
    event StreamingFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewProfitUnlockTime(uint48 timeSeconds);

    error InvalidFee(uint256 newFee);
    error AlreadySet();

    /// @notice Returns the amount of unlocked profit shares that will be burned
    function unlockedShares(
        ILMPVault.ProfitUnlockSettings storage profitUnlockSettings,
        AutoPoolToken.TokenData storage tokenData
    ) public view returns (uint256 shares) {
        uint256 fullTime = profitUnlockSettings.fullProfitUnlockTime;
        if (fullTime > block.timestamp) {
            shares = profitUnlockSettings.profitUnlockRate
                * (block.timestamp - profitUnlockSettings.lastProfitUnlockTime) / MAX_BPS_PROFIT;
        } else if (fullTime != 0) {
            shares = tokenData.balances[address(this)];
        }
    }

    function initializeFeeSettings(ILMPVault.AutoPoolFeeSettings storage settings) external {
        uint256 nextFeeTimeframe = uint48(block.timestamp + PERIODIC_FEE_TAKE_TIMEFRAME);
        settings.nextPeriodicFeeTake = nextFeeTimeframe;
        settings.navPerShareLastFeeMark = FEE_DIVISOR;
        settings.navPerShareLastFeeMarkTimestamp = block.timestamp;
        emit NextPeriodicFeeTakeSet(nextFeeTimeframe);
    }

    function burnUnlockedShares(
        ILMPVault.ProfitUnlockSettings storage profitUnlockSettings,
        AutoPoolToken.TokenData storage tokenData
    ) external {
        uint256 shares = unlockedShares(profitUnlockSettings, tokenData);
        if (shares == 0) {
            return;
        }
        if (profitUnlockSettings.fullProfitUnlockTime > block.timestamp) {
            profitUnlockSettings.lastProfitUnlockTime = uint48(block.timestamp);
        }
        tokenData.burn(address(this), shares);
    }

    function _calculateEffectiveNavPerShareLastFeeMark(
        ILMPVault.AutoPoolFeeSettings storage settings,
        uint256 currentBlock,
        uint256 currentNavPerShare,
        uint256 aumCurrent
    ) private view returns (uint256) {
        uint256 workingHigh = settings.navPerShareLastFeeMark;

        if (workingHigh == 0) {
            // If we got 0, we shouldn't increase it
            return 0;
        }

        if (!settings.rebalanceFeeHighWaterMarkEnabled) {
            // No calculations or checks to do in this case
            return workingHigh;
        }

        uint256 daysSinceLastFeeEarned = (currentBlock - settings.navPerShareLastFeeMarkTimestamp) / 60 / 60 / 24;

        if (daysSinceLastFeeEarned > 600) {
            return currentNavPerShare;
        }
        if (daysSinceLastFeeEarned > 60 && daysSinceLastFeeEarned <= 600) {
            uint8 decimals = ILMPVault(address(this)).decimals();

            uint256 one = 10 ** decimals;
            uint256 aumHighMark = settings.totalAssetsHighMark;

            // AUM_min = min(AUM_high, AUM_current)
            uint256 minAssets = aumCurrent < aumHighMark ? aumCurrent : aumHighMark;

            // AUM_max = max(AUM_high, AUM_current);
            uint256 maxAssets = aumCurrent > aumHighMark ? aumCurrent : aumHighMark;

            /// 0.999 * (AUM_min / AUM_max)
            // dividing by `one` because we need end up with a number in the 100's wei range
            uint256 g1 = ((999 * minAssets * one) / (maxAssets * one));

            /// 0.99 * (1 - AUM_min / AUM_max)
            // dividing by `10 ** (decimals() - 1)` because we need to divide 100 out for our % and then
            // we want to end up with a number in the 10's wei range
            uint256 g2 = (99 * (one - (minAssets * one / maxAssets))) / 10 ** (decimals - 1);

            uint256 gamma = g1 + g2;

            uint256 daysDiff = daysSinceLastFeeEarned - 60;
            for (uint256 i = 0; i < daysDiff / 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * (gamma ** 25 / 1e72) / 1000;
            }
            // slither-disable-next-line weak-prng
            for (uint256 i = 0; i < daysDiff % 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * gamma / 1000;
            }
        }
        return workingHigh;
    }

    function collectFees(
        uint256 totalAssets,
        uint256 currentTotalSupply,
        ILMPVault.AutoPoolFeeSettings storage settings,
        AutoPoolToken.TokenData storage tokenData
    ) external returns (uint256) {
        // If there's no supply then there should be no assets and so nothing
        // to actually take fees on
        // slither-disable-next-line incorrect-equality
        if (currentTotalSupply == 0) {
            return 0;
        }

        // slither-disable-next-line incorrect-equality
        if (settings.totalAssetsHighMark == 0) {
            // Initialize our high water mark to the current assets
            settings.totalAssetsHighMark = totalAssets;
        }

        // slither-disable-start timestamp
        // If current timestamp is greater than nextPeriodicFeeTake, operations need to happen for periodic fee.

        if (block.timestamp > settings.nextPeriodicFeeTake) {
            address periodicSink = settings.periodicFeeSink;

            // If there is a periodic fee and fee sink set, take the fee.
            if (settings.periodicFeeBps > 0 && periodicSink != address(0)) {
                uint256 periodicShares =
                    _collectPeriodicFees(periodicSink, settings.periodicFeeBps, currentTotalSupply, totalAssets);

                currentTotalSupply += periodicShares;
                tokenData.mint(periodicSink, periodicShares);
            }

            // If there is a pending periodic fee set, replace periodic fee with pending after fees already taken.
            uint256 pendingMgmtFeeBps = settings.pendingPeriodicFeeBps;

            if (pendingMgmtFeeBps > 0) {
                emit PeriodicFeeSet(pendingMgmtFeeBps);
                emit PendingPeriodicFeeSet(0);

                settings.periodicFeeBps = pendingMgmtFeeBps;
                settings.pendingPeriodicFeeBps = 0;
            }

            // Needs to be updated any time timestamp > `nextTakePeriodicFee` to keep up to date.
            settings.nextPeriodicFeeTake += uint48(PERIODIC_FEE_TAKE_TIMEFRAME);
            emit NextPeriodicFeeTakeSet(settings.nextPeriodicFeeTake);
        }

        // slither-disable-end timestamp
        uint256 currentNavPerShare = (totalAssets * FEE_DIVISOR) / currentTotalSupply;

        // If the high mark is disabled then this just returns the `navPerShareLastFeeMark`
        // Otherwise, it'll check if it needs to decay
        uint256 effectiveNavPerShareLastFeeMark =
            _calculateEffectiveNavPerShareLastFeeMark(settings, block.timestamp, currentNavPerShare, totalAssets);

        if (currentNavPerShare > effectiveNavPerShareLastFeeMark) {
            // Even if we aren't going to take the fee (haven't set a sink)
            // We still want to calculate so we can emit for off-chain analysis
            uint256 streamingFeeBps = settings.streamingFeeBps;
            uint256 profit = (currentNavPerShare - effectiveNavPerShareLastFeeMark) * currentTotalSupply;
            uint256 fees = profit.mulDiv(streamingFeeBps, (FEE_DIVISOR ** 2), Math.Rounding.Up);

            if (fees > 0) {
                currentTotalSupply = _mintStreamingFee(
                    tokenData, fees, streamingFeeBps, profit, currentTotalSupply, totalAssets, settings.feeSink
                );
                currentNavPerShare = (totalAssets * FEE_DIVISOR) / currentTotalSupply;
            }
        }

        // Two situations we're covering here
        //   1. If the high mark is disabled then we just always need to know the last
        //      time we evaluated fees so we can catch any run up. i.e. the `navPerShareLastFeeMark`
        //      can go down
        //   2. When the high mark is enabled, then we only want to set `navPerShareLastFeeMark`
        //      when it is greater than the last time we captured fees (or would have)
        if (currentNavPerShare > effectiveNavPerShareLastFeeMark || !settings.rebalanceFeeHighWaterMarkEnabled) {
            settings.navPerShareLastFeeMark = currentNavPerShare;
            settings.navPerShareLastFeeMarkTimestamp = block.timestamp;
            emit NewNavShareFeeMark(currentNavPerShare, block.timestamp);
        }

        // Set our new high water mark for totalAssets, regardless if we took fees
        if (settings.totalAssetsHighMark < totalAssets) {
            settings.totalAssetsHighMark = totalAssets;
            settings.totalAssetsHighMarkTimestamp = block.timestamp;
            emit NewTotalAssetsHighWatermark(settings.totalAssetsHighMark, settings.totalAssetsHighMarkTimestamp);
        }

        return currentTotalSupply;
    }

    function _mintStreamingFee(
        AutoPoolToken.TokenData storage tokenData,
        uint256 fees,
        uint256 streamingFeeBps,
        uint256 profit,
        uint256 currentTotalSupply,
        uint256 totalAssets,
        address sink
    ) private returns (uint256) {
        if (sink == address(0)) {
            return currentTotalSupply;
        }

        // Calculated separate from other mints as normal share mint is round down
        // Note: We use Lido's formula: from https://docs.lido.fi/guides/lido-tokens-integration-guide/#fees
        // suggested by: https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/486-H/624-best.md
        // but we scale down `profit` by FEE_DIVISOR
        uint256 streamingFeeShares = Math.mulDiv(
            streamingFeeBps * profit / FEE_DIVISOR,
            currentTotalSupply,
            (totalAssets * FEE_DIVISOR) - (streamingFeeBps * profit / FEE_DIVISOR),
            Math.Rounding.Up
        );
        tokenData.mint(sink, streamingFeeShares);
        currentTotalSupply += streamingFeeShares;

        emit Deposit(address(this), sink, 0, streamingFeeShares);
        emit FeeCollected(fees, sink, streamingFeeShares, profit, totalAssets);

        return currentTotalSupply;
    }

    /// @dev Collects periodic fees.
    function _collectPeriodicFees(
        address periodicSink,
        uint256 periodicFeeBps,
        uint256 currentTotalSupply,
        uint256 assets
    ) private returns (uint256 newShares) {
        // Periodic fee * assets used multiple places below, gas savings when calc here.
        uint256 periodicFeeMultAssets = periodicFeeBps * assets;

        // We calculate the shares using the same formula as streaming fees, without scaling down
        newShares = Math.mulDiv(
            periodicFeeMultAssets,
            currentTotalSupply,
            (assets * FEE_DIVISOR) - (periodicFeeMultAssets),
            Math.Rounding.Up
        );

        // Fee in assets that we are taking.
        uint256 fees = periodicFeeMultAssets.ceilDiv(FEE_DIVISOR);
        emit Deposit(address(this), periodicSink, 0, newShares);
        emit PeriodicFeeCollected(fees, periodicSink, newShares);

        return newShares;
    }

    /// @dev If set to 0, existing shares will unlock immediately and increase nav/share. This is intentional
    function setProfitUnlockPeriod(
        ILMPVault.ProfitUnlockSettings storage settings,
        AutoPoolToken.TokenData storage tokenData,
        uint48 newUnlockPeriodInSeconds
    ) external {
        settings.unlockPeriodInSeconds = newUnlockPeriodInSeconds;

        // If we are turning off the unlock, setting it to 0, then
        // unlock all existing shares
        if (newUnlockPeriodInSeconds == 0) {
            uint256 currentShares = tokenData.balances[address(this)];
            if (currentShares > 0) {
                settings.lastProfitUnlockTime = uint48(block.timestamp);
                tokenData.burn(address(this), currentShares);
            }

            // Reset vars so old values aren't used during a subsequent lockup
            settings.fullProfitUnlockTime = 0;
            settings.profitUnlockRate = 0;
        }

        emit NewProfitUnlockTime(newUnlockPeriodInSeconds);
    }

    function calculateProfitLocking(
        ILMPVault.ProfitUnlockSettings storage settings,
        AutoPoolToken.TokenData storage tokenData,
        uint256 feeShares,
        uint256 newTotalAssets,
        uint256 startTotalAssets,
        uint256 startTotalSupply,
        uint256 previousLockShares
    ) external returns (uint256) {
        uint256 unlockPeriod = settings.unlockPeriodInSeconds;

        // If there were existing shares and we set the unlock period to 0 they are immediately unlocked
        // so we don't have to worry about existing shares here. And if the period is 0 then we
        // won't be locking any new shares
        if (unlockPeriod == 0) {
            return startTotalSupply;
        }

        uint256 newLockShares = 0;
        uint256 previousLockToBurn = 0;
        uint256 effectiveTs = startTotalSupply;

        // The total supply we would need to not see a change in nav/share
        uint256 targetTotalSupply = newTotalAssets * (effectiveTs - feeShares) / startTotalAssets;

        if (effectiveTs > targetTotalSupply) {
            // Our actual total supply is greater than our target.
            // This means we would see a decrease in nav/share
            // See if we can burn any profit shares to offset that
            if (previousLockShares > 0) {
                uint256 diff = effectiveTs - targetTotalSupply;
                if (previousLockShares >= diff) {
                    previousLockToBurn = diff;
                    effectiveTs -= diff;
                } else {
                    previousLockToBurn = previousLockShares;
                    effectiveTs -= previousLockShares;
                }
            }
        }

        if (targetTotalSupply > effectiveTs) {
            // Our actual total supply is less than our target.
            // This means we would see an increase in nav/share (due to gains) which we can't allow
            // We need to mint shares to the vault to offset
            newLockShares = targetTotalSupply - effectiveTs;
            effectiveTs += newLockShares;
        }

        // We know how many shares should be locked at this point
        // Mint or burn what we need to match if necessary
        uint256 totalLockShares = previousLockShares - previousLockToBurn + newLockShares;
        if (totalLockShares > previousLockShares) {
            uint256 mintAmount = totalLockShares - previousLockShares;
            tokenData.mint(address(this), mintAmount);
            startTotalSupply += mintAmount;
        } else if (totalLockShares < previousLockShares) {
            uint256 burnAmount = previousLockShares - totalLockShares;
            tokenData.burn(address(this), burnAmount);
            startTotalSupply -= burnAmount;
        }

        // If we're going to end up with no profit shares, zero the rate
        // We don't need to 0 the other timing vars if we just zero the rate
        if (totalLockShares == 0) {
            settings.profitUnlockRate = 0;
        }

        // We have shares and they are going to unlocked later
        if (totalLockShares > 0 && unlockPeriod > 0) {
            _updateProfitUnlockTimings(
                settings, unlockPeriod, previousLockToBurn, previousLockShares, newLockShares, totalLockShares
            );
        }

        return startTotalSupply;
    }

    function _updateProfitUnlockTimings(
        ILMPVault.ProfitUnlockSettings storage settings,
        uint256 unlockPeriod,
        uint256 previousLockToBurn,
        uint256 previousLockShares,
        uint256 newLockShares,
        uint256 totalLockShares
    ) private {
        uint256 previousLockTime;
        uint256 fullUnlockTime = settings.fullProfitUnlockTime;

        // Determine how much time is left for the remaining previous profit shares
        if (fullUnlockTime > block.timestamp) {
            previousLockTime = (previousLockShares - previousLockToBurn) * (fullUnlockTime - block.timestamp);
        }

        // Amount of time it will take to unlock all shares, weighted avg over current and new shares
        uint256 newUnlockPeriod = (previousLockTime + newLockShares * unlockPeriod) / totalLockShares;

        // Rate at which totalLockShares will unlock
        settings.profitUnlockRate = totalLockShares * MAX_BPS_PROFIT / newUnlockPeriod;

        // Time the full of amount of totalLockShares will be unlocked
        settings.fullProfitUnlockTime = uint48(block.timestamp + newUnlockPeriod);
        settings.lastProfitUnlockTime = uint48(block.timestamp);
    }

    /// @notice Enable or disable the high water mark on the rebalance fee
    /// @dev Will revert if set to the same value
    function setRebalanceFeeHighWaterMarkEnabled(
        ILMPVault.AutoPoolFeeSettings storage feeSettings,
        bool enabled
    ) external {
        if (feeSettings.rebalanceFeeHighWaterMarkEnabled == enabled) {
            revert AlreadySet();
        }

        feeSettings.rebalanceFeeHighWaterMarkEnabled = enabled;

        emit RebalanceFeeHighWaterMarkEnabledSet(enabled);
    }

    /// @notice Set the fee that will be taken when profit is realized
    /// @dev Resets the high water to current value
    /// @param fee Percent. 100% == 10000
    function setStreamingFeeBps(ILMPVault.AutoPoolFeeSettings storage feeSettings, uint256 fee) external {
        if (fee >= FEE_DIVISOR) {
            revert InvalidFee(fee);
        }

        feeSettings.streamingFeeBps = fee;

        ILMPVault vault = ILMPVault(address(this));

        // Set the high mark when we change the fee so we aren't able to go farther back in
        // time than one debt reporting and claim fee's against past profits
        uint256 supply = vault.totalSupply();
        if (supply > 0) {
            feeSettings.navPerShareLastFeeMark = (vault.totalAssets() * FEE_DIVISOR) / supply;
        } else {
            // The default high mark is 1:1. We don't want to be able to take
            // fee's before the first debt reporting
            // Before a rebalance, everything will be in idle and we don't want to take
            // fee's on pure idle
            feeSettings.navPerShareLastFeeMark = FEE_DIVISOR;
        }

        emit StreamingFeeSet(fee);
    }

    /// @notice Set the periodic fee taken.
    /// @dev Depending on time until next fee take, may update periodicFeeBps directly or queue fee.
    /// @param fee Fee to update periodic fee to.
    function setPeriodicFeeBps(ILMPVault.AutoPoolFeeSettings storage feeSettings, uint256 fee) external {
        if (fee > MAX_PERIODIC_FEE_BPS) {
            revert InvalidFee(fee);
        }

        /**
         * If the current timestamp is greater than the next fee take minus 45 days, we are withing the timeframe
         *      that we do not want to be able to set a new periodic fee, so we set `pendingPeriodicFeeBps` instead.
         *      This will be set as `periodicFeeBps` when periodic fees are taken.
         *
         * Fee checked to fit into uint16 above, able to be wrapped without safe cast here.
         */
        // slither-disable-next-line timestamp
        if (block.timestamp > feeSettings.nextPeriodicFeeTake - PERIODIC_FEE_CHANGE_CUTOFF) {
            emit PendingPeriodicFeeSet(fee);
            feeSettings.pendingPeriodicFeeBps = uint16(fee);
        } else {
            emit PeriodicFeeSet(fee);
            feeSettings.periodicFeeBps = uint16(fee);
        }
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(ILMPVault.AutoPoolFeeSettings storage feeSettings, address newFeeSink) external {
        emit FeeSinkSet(newFeeSink);

        // Zero is valid. One way to disable taking fees
        // slither-disable-next-line missing-zero-check
        feeSettings.feeSink = newFeeSink;
    }

    /// @notice Sets the address that will receive periodic fees.
    /// @dev Zero address allowable.  Disables fees.
    /// @param newPeriodicFeeSink New periodic fee address.
    function setPeriodicFeeSink(
        ILMPVault.AutoPoolFeeSettings storage feeSettings,
        address newPeriodicFeeSink
    ) external {
        emit PeriodicFeeSinkSet(newPeriodicFeeSink);

        // slither-disable-next-line missing-zero-check
        feeSettings.periodicFeeSink = newPeriodicFeeSink;
    }
}
