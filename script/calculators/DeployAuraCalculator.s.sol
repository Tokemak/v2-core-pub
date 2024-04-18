// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { AuraCalculator } from "src/stats/calculators/AuraCalculator.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";

contract DeployAuraCalculator is BaseScript {
    bytes32 internal auraTemplateId = keccak256("aura");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        AuraCalculator auraTemplate = new AuraCalculator(systemRegistry, constants.ext.auraBooster);
        statsCalcFactory.removeTemplate(auraTemplateId);
        statsCalcFactory.registerTemplate(auraTemplateId, address(auraTemplate));

        vm.stopBroadcast();
    }
}
