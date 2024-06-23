// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";

contract TestIncentiveCalculator {
    address internal _lpToken;
    address internal _poolAddress;

    function lpToken() public view virtual returns (address) {
        return _lpToken;
    }

    function poolAddress() public view virtual returns (address) {
        return _poolAddress;
    }

    function pool() public view virtual returns (address) {
        return _poolAddress;
    }

    function setLpToken(address lpToken_) public {
        _lpToken = lpToken_;
    }

    function setPoolAddress(address poolAddress_) public {
        _poolAddress = poolAddress_;
    }

    function current() external pure returns (IDexLSTStats.DexLSTStatsData memory) {
        uint256 lastSnapshotTimestamp = 1;
        uint256 feeApr = 2;
        uint256[] memory reservesInEth = new uint256[](1);
        reservesInEth[0] = 3;

        IDexLSTStats.StakingIncentiveStats memory stakingIncentiveStats = _getStakingIncentiveStats();

        ILSTStats.LSTStatsData[] memory lstStatsData = _getLSTStatsData();

        return IDexLSTStats.DexLSTStatsData(
            lastSnapshotTimestamp, feeApr, reservesInEth, stakingIncentiveStats, lstStatsData
        );
    }

    function _getStakingIncentiveStats() private pure returns (IDexLSTStats.StakingIncentiveStats memory stats) {
        uint256 safeTotalSupply = 1;

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(2);

        uint256[] memory annualizedRewardAmounts = new uint256[](1);
        annualizedRewardAmounts[0] = 3;

        uint40[] memory periodFinishForRewards = new uint40[](1);
        periodFinishForRewards[0] = 4;

        uint8 incentiveCredits = 5;

        stats = IDexLSTStats.StakingIncentiveStats(
            safeTotalSupply, rewardTokens, annualizedRewardAmounts, periodFinishForRewards, incentiveCredits
        );
    }

    function _getLSTStatsData() private pure returns (ILSTStats.LSTStatsData[] memory stats) {
        stats = new ILSTStats.LSTStatsData[](1);

        uint256 lastSnapshotTimestamp = 1;
        uint256 baseApr = 2;
        int256 discount = 3;

        uint24[10] memory discountHistory = [
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4),
            uint24(4)
        ];
        uint40[5] memory discountTimestampByPercent = [uint40(5), uint40(5), uint40(5), uint40(5), uint40(5)];

        stats[0] = ILSTStats.LSTStatsData(
            lastSnapshotTimestamp, baseApr, discount, discountHistory, discountTimestampByPercent
        );
    }
}
