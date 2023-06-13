// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Stats } from "src/stats/Stats.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ICurveRegistry } from "src/interfaces/external/curve/ICurveRegistry.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";

/// @notice Calculate stats for a Curve V1 StableSwap pool whose LP is staked in Convex
contract CurveV1ConvexStatsCalculator is BaseStatsCalculator, Initializable {
    address private _addressId;
    bytes32 private _aprId;

    ICurveRegistry public immutable curveRegistry;
    IConvexBooster public immutable convexBooster;

    address public curvePoolAddress;
    uint256 public convexPoolId;
    uint256 public lastIncentiveApr;

    struct InitData {
        address curvePoolAddress;
        uint256 convexPoolId;
    }

    error InvalidNumDependentAprIds(uint256 num);
    error ConvexPoolShutdown(uint256 poolId);
    error MismatchLPTokens(address convexQueried, address curveQueried, address curvePool);

    constructor(
        ISystemRegistry _systemRegistry,
        ICurveRegistry _curveRegistry,
        IConvexBooster _convexBooster
    ) BaseStatsCalculator(_systemRegistry) {
        Errors.verifyNotZero(address(_curveRegistry), "_curveRegistry");
        Errors.verifyNotZero(address(_convexBooster), "_convexBooster");

        curveRegistry = _curveRegistry;
        convexBooster = _convexBooster;
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return _addressId;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        Errors.verifyNotZero(decodedInitData.curvePoolAddress, "decodedInitData.curvePoolAddress");
        Errors.verifyNotZero(decodedInitData.convexPoolId, "decodedInitData.convexPoolId");

        curvePoolAddress = decodedInitData.curvePoolAddress;
        convexPoolId = decodedInitData.convexPoolId;
        _addressId = address(uint160(decodedInitData.convexPoolId));

        // Ensure the supplied configuration data is matching up
        // and the pools are in good standing
        address curveQueriedLpToken = curveRegistry.get_lp_token(decodedInitData.curvePoolAddress);
        Errors.verifyNotZero(curveQueriedLpToken, "curveQueriedLpToken");
        (address convexQueriedLpToken,,,,, bool shutdown) = convexBooster.poolInfo(decodedInitData.convexPoolId);
        if (shutdown) {
            revert ConvexPoolShutdown(decodedInitData.convexPoolId);
        }
        if (curveQueriedLpToken != convexQueriedLpToken) {
            revert MismatchLPTokens(convexQueriedLpToken, curveQueriedLpToken, decodedInitData.curvePoolAddress);
        }
        _aprId = keccak256(abi.encode("curveV1Convex", curveQueriedLpToken, decodedInitData.convexPoolId));

        if (dependentAprIds.length != 1) {
            revert InvalidNumDependentAprIds(dependentAprIds.length);
        }

        // The only dependency is on the Curve pool itself whose calculators use the
        // lp token of the pool as their ids
        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();
        IStatsCalculator calculator = registry.getCalculator(dependentAprIds[0]);
        if (calculator.getAddressId() != curveQueriedLpToken) {
            revert Stats.CalculatorAssetMismatch(dependentAprIds[0], address(calculator), curveQueriedLpToken);
        }
        calculators.push(calculator);
    }

    /// @inheritdoc IStatsCalculator
    function current() external view override returns (Stats.CalculatedStats memory) {
        return Stats.CalculatedStats({ statsType: Stats.StatsType.DEX, data: "", dependentStats: calculators });
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() external pure returns (bool takeSnapshot) {
        // TODO: implement real snapshot logic
        return true;
    }

    /// @notice Capture stat data about this setup
    /// @dev This is protected by the STATS_SNAPSHOT_ROLE
    function _snapshot() internal override {
        lastIncentiveApr = block.number / 1000;
    }
}
