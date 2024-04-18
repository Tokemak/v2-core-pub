// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,var-name-mixedcase

import { BaseScript } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { DeployIncentiveCalculatorBase } from "script/calculators/DeployIncentiveCalculatorBase.sol";

contract DeployRethWeth is BaseScript, DeployIncentiveCalculatorBase {
    bytes32 internal auraTemplateId = keccak256("aura");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        address pool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        address LpToken = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        address poolCalculator = 0x3e097470a99100ED038688A7C548Fb7cB59b4086;
        address rewarder = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;

        _setupIncentiveCalculatorBase(
            statsCalcFactory,
            "Aura + Balancer rETH/WETH",
            auraTemplateId,
            poolCalculator,
            constants.tokens.aura,
            rewarder,
            LpToken,
            pool
        );

        vm.stopBroadcast();
    }
}
