// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";

contract DeployConvexCalculator is BaseScript {
    bytes32 internal convexTemplateId = keccak256("convex");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        ConvexCalculator convexTemplate = new ConvexCalculator(systemRegistry, constants.ext.convexBooster);
        statsCalcFactory.removeTemplate(convexTemplateId);
        statsCalcFactory.registerTemplate(convexTemplateId, address(convexTemplate));

        vm.stopBroadcast();
    }
}
