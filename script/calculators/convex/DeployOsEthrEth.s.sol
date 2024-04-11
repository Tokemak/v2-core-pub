// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Roles } from "src/libs/Roles.sol";

import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";

import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";

import { DeployIncentiveCalculatorBase } from "script/calculators/DeployIncentiveCalculatorBase.sol";

contract DeployOsEthrEth is BaseScript, DeployIncentiveCalculatorBase {
    bytes32 internal convexTemplateId = keccak256("convex");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;
        address curveV2cbEthEthCalculator = 0x177B9FB826F79a2c0d590F418AC9517E71eA4272;
        address convexV2cbEthEthRewarder = 0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699;
        _setupIncentiveCalculatorBase(
            statsCalcFactory,
            "Convex + Curve V2 cbETH/ETH",
            convexTemplateId,
            curveV2cbEthEthCalculator,
            constants.tokens.cvx,
            convexV2cbEthEthRewarder,
            curveV2cbEthEthLpToken,
            curveV2cbEthEthPool
        );

        vm.stopBroadcast();
    }
}
