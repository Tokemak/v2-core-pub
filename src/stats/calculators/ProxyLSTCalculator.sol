// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";

contract ProxyLSTCalculator is ILSTStats, BaseStatsCalculator, Initializable {
    ILSTStats public statsCalculator;
    address public lstTokenAddress;

    bytes32 private _aprId;
    bool private _isRebasing;

    struct InitData {
        address lstTokenAddress;
        address statsCalculator;
        bool isRebasing;
    }

    constructor(ISystemRegistry _systemRegistry) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        lstTokenAddress = decodedInitData.lstTokenAddress;
        statsCalculator = ILSTStats(decodedInitData.statsCalculator);
        _aprId = keccak256(abi.encode("lst", lstTokenAddress));
        _isRebasing = decodedInitData.isRebasing;
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return lstTokenAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    function _snapshot() internal pure override {
        revert NoSnapshotTaken();
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public pure override returns (bool takeSnapshot) {
        return false;
    }

    /// @inheritdoc ILSTStats
    function current() external returns (LSTStatsData memory stats) {
        return statsCalculator.current();
    }

    /// @inheritdoc ILSTStats
    function calculateEthPerToken() external view returns (uint256) {
        return statsCalculator.calculateEthPerToken();
    }

    /// @inheritdoc ILSTStats
    function isRebasing() external view returns (bool) {
        return _isRebasing;
    }
}
