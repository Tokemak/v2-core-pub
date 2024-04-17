// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { DeployIncentiveCalculatorBase } from "script/calculators/DeployIncentiveCalculatorBase.sol";

contract DeployOsEthrEth is BaseScript, DeployIncentiveCalculatorBase {
    bytes32 internal convexTemplateId = keccak256("convex");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast();

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        address pool = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        address lpToken = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        address poolCalculator = 0x3126b72597420A61FB67f50c8f1e7b59359cfB24;
        address rewarder = 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e;

        _setupIncentiveCalculatorBase(
            statsCalcFactory,
            "Convex + Curve osETH/rETH",
            convexTemplateId,
            poolCalculator,
            constants.tokens.cvx,
            rewarder,
            lpToken,
            pool
        );

        vm.stopBroadcast();
    }
}
