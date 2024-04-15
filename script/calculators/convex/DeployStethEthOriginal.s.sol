// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Systems } from "script/utils/Constants.sol";
import { BaseScript } from "script/BaseScript.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { DeployIncentiveCalculatorBase } from "script/calculators/DeployIncentiveCalculatorBase.sol";

contract DeployStEthOriginal is BaseScript, DeployIncentiveCalculatorBase {
    bytes32 internal convexTemplateId = keccak256("convex");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        // stETH/ETH Original
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveStEthOriginalCalculator = 0xaed4850Ce877C0e0b051EbfF9286074C9378205c;
        address convexStEthOriginalRewarder = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;
        _setupIncentiveCalculatorBase(
            statsCalcFactory,
            "Convex + Curve stETH/ETH Original",
            convexTemplateId,
            curveStEthOriginalCalculator,
            constants.tokens.cvx,
            convexStEthOriginalRewarder,
            curveStEthOriginalLpToken,
            curveStEthOriginalPool
        );

        vm.stopBroadcast();
    }
}
