// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @title Return stats on base LSTs
interface ILSTStats {
    struct LSTStatsData {
        uint256 lastSnapshotTimestamp;
        uint256 baseApr;
        int256 discount; // positive number is a discount, negative is a premium
        uint24[10] discountHistory; // 7 decimal precision
        uint40[5] discountTimestampByPercent; // each index is the timestamp that the token reached that discount
        uint256[] slashingCosts;
        uint256[] slashingTimestamps;
    }

    /// @notice Used to transfer LST snapshot data to other chain.
    struct LSTDestinationInfo {
        uint256 snapshotTimestamp;
        uint256 newBaseApr;
        uint256 currentEthPerToken;
    }

    /// @notice Get the current stats for the LST
    /// @dev Returned data is a combination of current data and filtered snapshots
    /// @return lstStatsData current data on the LST
    function current() external returns (LSTStatsData memory lstStatsData);

    /// @notice Get the EthPerToken (or Share) for the LST
    /// @return ethPerShare the backing eth for the LST
    function calculateEthPerToken() external view returns (uint256 ethPerShare);

    /// @notice Get if the underlying LST token is rebasing
    /// @return rebasing is true if the lst is a rebasing token
    function isRebasing() external view returns (bool rebasing);
}
