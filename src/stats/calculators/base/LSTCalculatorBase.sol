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

    event DiscountSnapshotTaken(uint256 priorTimestamp, uint24 discount, uint256 currentTimestamp);

    event SlashingEventRecorded(uint256 slashingCost, uint256 slashingTimestamp);

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
        updateDiscountTimestampByPercent();
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
            updateDiscountTimestampByPercent();
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

    function updateDiscountTimestampByPercent() private {
        uint256 discountHistoryLength = discountHistory.length;
        uint40 previousDiscount =
            discountHistory[(discountHistoryIndex + discountHistoryLength - 2) % discountHistoryLength];
        uint40 currentDiscount =
            discountHistory[(discountHistoryIndex + discountHistoryLength - 1) % discountHistoryLength];

        // for each percent slot ask:
        // "was this not in violation last round and now in violation this round?"
        // if yes, overwrite that slot in discountTimestampByPercent with the current timestamp
        // if no, do nothing
        // TODO: There is gas optimization here with early stopping

        uint40 discountPercent;
        bool inViolationLastSnapshot;
        bool inViolationThisSnapshot;

        // cached for gas efficiency see slither: cache-array-length
        uint40 discountTimestampByPercentLength = uint40(discountTimestampByPercent.length);

        // iterate over 1-5% discounts. max discount = discountTimestampByPercent.length percent
        for (uint40 i; i < discountTimestampByPercentLength; ++i) {
            // 1e5 in discountHistory means a 1% LST discount.
            discountPercent = (i + 1) * 1e5;

            inViolationLastSnapshot = discountPercent <= previousDiscount;
            inViolationThisSnapshot = discountPercent <= currentDiscount;

            if (inViolationThisSnapshot && !inViolationLastSnapshot) {
                discountTimestampByPercent[i] = uint40(block.timestamp);
            }
        }
    }

    function updateDiscountHistory(uint256 backing) private {
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
        // Log event for discount snapshot
        // slither-disable-next-line reentrancy-events
        emit DiscountSnapshotTaken(lastDiscountSnapshotTimestamp, trackedDiscount, block.timestamp);
        lastDiscountSnapshotTimestamp = block.timestamp;
    }

    /// @inheritdoc ILSTStats
    function calculateEthPerToken() public view virtual returns (uint256);

    /// @inheritdoc ILSTStats
    function isRebasing() public view virtual returns (bool);
}
