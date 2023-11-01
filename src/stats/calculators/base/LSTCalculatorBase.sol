// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Stats } from "src/stats/Stats.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

abstract contract LSTCalculatorBase is ILSTStats, BaseStatsCalculator, Initializable {
    /// @notice time in seconds between apr snapshots
    uint256 public constant APR_SNAPSHOT_INTERVAL_IN_SEC = 3 * 24 * 60 * 60; // 3 days

    /// @notice time in seconds for the initialization period
    uint256 public constant APR_FILTER_INIT_INTERVAL_IN_SEC = 9 * 24 * 60 * 60; // 9 days

    /// @notice time in seconds between slashing snapshots
    uint256 public constant SLASHING_SNAPSHOT_INTERVAL_IN_SEC = 24 * 60 * 60; // 1 day

    /// @notice time in seconds between discount snapshots
    uint256 public constant DISCOUNT_SNAPSHOT_INTERVAL_IN_SEC = 24 * 60 * 60; // 1 day

    /// @notice alpha for filter
    uint256 public constant ALPHA = 1e17; // 0.1; must be 0 < x <= 1e18

    /// @notice lstTokenAddress is the address for the LST that the stats are for
    address public lstTokenAddress;

    /// @notice ethPerToken at the last snapshot for base apr
    uint256 public lastBaseAprEthPerToken;

    /// @notice timestamp of the last snapshot for base apr
    uint256 public lastBaseAprSnapshotTimestamp;

    /// @notice timestamp of the last discount snapshot
    uint256 public lastDiscountSnapshotTimestamp;

    /// @notice ethPerToken at the last snapshot for slashing events
    uint256 public lastSlashingEthPerToken;

    /// @notice timestamp of the last snapshot for base apr
    uint256 public lastSlashingSnapshotTimestamp;

    /// @notice filtered base apr
    uint256 public baseApr;

    /// @notice list of slashing costs (slashing / value at the time)
    uint256[] public slashingCosts;

    /// @notice list of timestamps associated with slashing events
    uint256[] public slashingTimestamps;

    /// @notice the last 10 daily discount/premium values for the token
    uint24[10] public discountHistory;

    /// @notice each index is the timestamp that the token reached that discount (e.g., 1pct = 0 index)
    uint40[5] public discountTimestampByPercent;

    // TODO: verify that we save space by using a uint8. It should be packed with the bool & bytes32 below
    /// @dev the next index in the discountHistory buffer to be written
    uint8 private discountHistoryIndex;

    /// @notice indicates if baseApr filter is initialized
    bool public baseAprFilterInitialized;

    bytes32 private _aprId;

    struct InitData {
        address lstTokenAddress;
    }

    event BaseAprSnapshotTaken(
        uint256 priorEthPerToken,
        uint256 priorTimestamp,
        uint256 currentEthPerToken,
        uint256 currentTimestamp,
        uint256 priorBaseApr,
        uint256 currentBaseApr
    );

    event SlashingSnapshotTaken(
        uint256 priorEthPerToken, uint256 priorTimestamp, uint256 currentEthPerToken, uint256 currentTimestamp
    );

    event SlashingEventRecorded(uint256 slashingCost, uint256 slashingTimestamp);

    uint40 private timestampOfDecayStart;
    // the timestampOfDecayStart timestamp of the start of a discount episode.
    // discount episode is the stretch of concurrent days where the LST discount  > 1%
    // this is needed to prevent retracing on the way back up
    uint40[5] private percentileByIndex = [1e5, 2e5, 3e5, 4e5, 5e5]; // 1%, 2%, 3%, 4%, 5%

    constructor(ISystemRegistry _systemRegistry) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        lstTokenAddress = decodedInitData.lstTokenAddress;
        _aprId = Stats.generateRawTokenIdentifier(lstTokenAddress);

        uint256 currentEthPerToken = calculateEthPerToken();
        lastBaseAprEthPerToken = currentEthPerToken;
        lastBaseAprSnapshotTimestamp = block.timestamp;
        baseAprFilterInitialized = false;
        lastSlashingEthPerToken = currentEthPerToken;
        lastSlashingSnapshotTimestamp = block.timestamp;

        // slither-disable-next-line reentrancy-benign
        updateDiscountHistory(currentEthPerToken);

        // // TODO: make slither happy, but this feature needs to be implemented
        // discountTimestampByPercent = [0, 0, 0, 0, 0];
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return lstTokenAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    function _snapshot() internal override {
        uint256 currentEthPerToken = calculateEthPerToken();
        if (_timeForAprSnapshot()) {
            uint256 currentApr = Stats.calculateAnnualizedChangeMinZero(
                lastBaseAprSnapshotTimestamp, lastBaseAprEthPerToken, block.timestamp, currentEthPerToken
            );
            uint256 newBaseApr;
            if (baseAprFilterInitialized) {
                newBaseApr = Stats.getFilteredValue(ALPHA, baseApr, currentApr);
            } else {
                // Speed up the baseApr filter ramp
                newBaseApr = currentApr;
                baseAprFilterInitialized = true;
            }

            emit BaseAprSnapshotTaken(
                lastBaseAprEthPerToken,
                lastBaseAprSnapshotTimestamp,
                currentEthPerToken,
                block.timestamp,
                baseApr,
                newBaseApr
            );

            baseApr = newBaseApr;
            lastBaseAprEthPerToken = currentEthPerToken;
            lastBaseAprSnapshotTimestamp = block.timestamp;
        }

        if (_timeForDiscountSnapshot()) {
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            updateDiscountHistory(currentEthPerToken);
            updateDiscountTimestampbyPercent();
        }

        if (_hasSlashingOccurred(currentEthPerToken)) {
            uint256 cost = Stats.calculateUnannualizedNegativeChange(lastSlashingEthPerToken, currentEthPerToken);
            slashingCosts.push(cost);
            slashingTimestamps.push(block.timestamp);

            emit SlashingEventRecorded(cost, block.timestamp);
            emit SlashingSnapshotTaken(
                lastSlashingEthPerToken, lastSlashingSnapshotTimestamp, currentEthPerToken, block.timestamp
            );

            lastSlashingEthPerToken = currentEthPerToken;
            lastSlashingSnapshotTimestamp = block.timestamp;
        } else if (_timeForSlashingSnapshot()) {
            emit SlashingSnapshotTaken(
                lastSlashingEthPerToken, lastSlashingSnapshotTimestamp, currentEthPerToken, block.timestamp
            );
            lastSlashingEthPerToken = currentEthPerToken;
            lastSlashingSnapshotTimestamp = block.timestamp;
        }
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view override returns (bool) {
        // slither-disable-start timestamp
        return _timeForAprSnapshot() || _timeForDiscountSnapshot() || _hasSlashingOccurred(calculateEthPerToken())
            || _timeForSlashingSnapshot();
        // slither-disable-end timestamp
    }

    function _timeForAprSnapshot() private view returns (bool) {
        if (baseAprFilterInitialized) {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastBaseAprSnapshotTimestamp + APR_SNAPSHOT_INTERVAL_IN_SEC;
        } else {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastBaseAprSnapshotTimestamp + APR_FILTER_INIT_INTERVAL_IN_SEC;
        }
    }

    function _timeForDiscountSnapshot() private view returns (bool) {
        // slither-disable-next-line timestamp
        return block.timestamp >= lastDiscountSnapshotTimestamp + DISCOUNT_SNAPSHOT_INTERVAL_IN_SEC;
    }

    function _timeForSlashingSnapshot() private view returns (bool) {
        // slither-disable-next-line timestamp
        return block.timestamp >= lastSlashingSnapshotTimestamp + SLASHING_SNAPSHOT_INTERVAL_IN_SEC;
    }

    function _hasSlashingOccurred(uint256 currentEthPerToken) private view returns (bool) {
        return currentEthPerToken < lastSlashingEthPerToken;
    }

    /// @inheritdoc ILSTStats
    function current() external returns (LSTStatsData memory) {
        uint256 lastSnapshotTimestamp;

        // return the most recent snapshot timestamp
        // the timestamp is used by the LMP to ensure that snapshots are occurring
        // so it is indifferent to which snapshot has occurred
        // slither-disable-next-line timestamp
        if (lastBaseAprSnapshotTimestamp < lastSlashingSnapshotTimestamp) {
            lastSnapshotTimestamp = lastSlashingSnapshotTimestamp;
        } else {
            lastSnapshotTimestamp = lastBaseAprSnapshotTimestamp;
        }

        return LSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            baseApr: baseApr,
            discount: calculateDiscount(calculateEthPerToken()),
            discountHistory: discountHistory,
            discountTimestampByPercent: discountTimestampByPercent,
            slashingCosts: slashingCosts,
            slashingTimestamps: slashingTimestamps
        });
    }

    function calculateDiscount(uint256 backing) private returns (int256) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        // slither-disable-next-line reentrancy-benign
        uint256 price = pricer.getPriceInEth(lstTokenAddress);

        // result is 1e18
        uint256 priceToBacking;
        if (isRebasing()) {
            priceToBacking = price;
        } else {
            // price is always 1e18 and backing is in eth, which is 1e18
            priceToBacking = price * 1e18 / backing;
        }

        // positive value is a discount; negative value is a premium
        return 1e18 - int256(priceToBacking);
    }

    function _handleStartToDecay(uint40 currentDiscount) private {
        // save timestampOfDecayStart as the start of this decay episode
        // don't overwrite any values that are newer than timestampOfDecayStart in the same discount
        timestampOfDecayStart = uint40(block.timestamp);
        for (uint256 i; i < 5; i++) {
            if (currentDiscount >= percentileByIndex[i]) {
                // overwrite the ith percentile slot with the current timestamp
                discountTimestampByPercent[i] = uint40(block.timestamp);
            } else {
                // early stopping if the discount is less than 1% then it is also less than 2% etc
                break;
            }
        }
    }

    function _handleIncreaseDecay(uint40 currentDiscount) private {
        for (uint256 i; i < 5; i++) {
            // don't overwrite any timestamps that were recorded as part of this discount episode
            if ((currentDiscount >= percentileByIndex[i]) && (discountTimestampByPercent[i] < timestampOfDecayStart)) {
                discountTimestampByPercent[i] = uint40(block.timestamp);
            } else if (currentDiscount < percentileByIndex[i]) {
                // early stopping if the discount is less than 1% then it is also less than 2% etc
                break;
            }
        }
    }

    function _getCurrentDiscount() private view returns (uint40) {
        if (discountHistoryIndex != 0) {
            return discountHistory[discountHistoryIndex - 1];
        } else {
            return discountHistory[9];
        }
    }

    function _getPreviousDiscount() private view returns (uint40) {
        if (discountHistoryIndex == 0) {
            return discountHistory[8];
        } else if (discountHistoryIndex == 1) {
            return discountHistory[9];
        } else {
            return discountHistory[discountHistoryIndex - 2];
        }
    }

    function updateDiscountTimestampbyPercent() private {
        uint40 currentDiscount = _getCurrentDiscount();
        uint40 previousDiscount = _getPreviousDiscount();

        // 1e5 == 1% in the discountHistory array
        if (currentDiscount >= 1e5) {
            if (previousDiscount < 1e5) {
                _handleStartToDecay(currentDiscount);
            } else {
                if (currentDiscount > previousDiscount) {
                    _handleIncreaseDecay(currentDiscount);
                }
            }
        } // all other end points of this decision tree dont modify discountTimestampByPercent
    }

    function updateDiscountHistory(uint256 backing) private {
        // TODO: verify that the precision loss is worth it
        // reduce precision from 18 to 7 to reduce costs
        int256 discount = calculateDiscount(backing) / 1e11;
        uint24 trackedDiscount;
        if (discount <= 0) {
            trackedDiscount = 0;
        } else if (discount >= 1e7) {
            trackedDiscount = 1e7;
        } else {
            trackedDiscount = uint24(uint256(discount));
        }

        discountHistory[discountHistoryIndex] = trackedDiscount;
        discountHistoryIndex = (discountHistoryIndex + 1) % uint8(discountHistory.length);
        lastDiscountSnapshotTimestamp = block.timestamp;
    }

    /// @inheritdoc ILSTStats
    function calculateEthPerToken() public view virtual returns (uint256);

    /// @inheritdoc ILSTStats
    function isRebasing() public view virtual returns (bool);
}
