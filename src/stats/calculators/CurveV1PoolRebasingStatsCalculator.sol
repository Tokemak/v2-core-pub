// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { CurvePoolRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolRebasingCalculatorBase.sol";
import { ICurveV1StableSwap } from "src/interfaces/external/curve/ICurveV1StableSwap.sol";
import { ICurveOwner } from "src/interfaces/external/curve/ICurveOwner.sol";

/// @title Curve V1 Pool With Rebasing Tokens
/// @notice Calculate stats for a Curve V1 StableSwap pool
contract CurveV1PoolRebasingStatsCalculator is CurvePoolRebasingCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) CurvePoolRebasingCalculatorBase(_systemRegistry) { }

    function getVirtualPrice() internal override returns (uint256 virtualPrice) {
        ICurveV1StableSwap pool = ICurveV1StableSwap(poolAddress);
        ICurveOwner(pool.owner()).withdraw_admin_fees(address(pool));

        return pool.get_virtual_price();
    }
}
