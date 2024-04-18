// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { console } from "forge-std/console.sol";

abstract contract DeployIncentiveCalculatorBase {
    function _setupIncentiveCalculatorBase(
        StatsCalculatorFactory statsFactory,
        string memory title,
        bytes32 aprTemplateId,
        address poolCalculator,
        address platformToken,
        address rewarder,
        address lpToken,
        address pool
    ) internal returns (address) {
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: rewarder,
            platformToken: platformToken,
            underlyerStats: poolCalculator,
            lpToken: lpToken,
            pool: pool
        });

        bytes memory encodedInitData = abi.encode(initData);

        address calculatorAddress = statsFactory.create(aprTemplateId, new bytes32[](0), encodedInitData);
        console.log("-----------------");

        console.log(string.concat(title, " calculator address: "), calculatorAddress);
        console.log(
            "lastSnapshotTimestamp: ", IncentiveCalculatorBase(calculatorAddress).current().lastSnapshotTimestamp
        );

        console.log("-----------------");

        return calculatorAddress;
    }
}
