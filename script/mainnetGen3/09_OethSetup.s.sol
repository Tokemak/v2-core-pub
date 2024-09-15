// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { OethLSTCalculator } from "src/stats/calculators/OethLSTCalculator.sol";

import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { Stats } from "src/stats/Stats.sol";
import { Calculators } from "script/core/Calculators.sol";

contract OEthSetup is Script, Calculators {
    Constants.Values public constants;

    // Incentive Template Ids
    bytes32 internal convexTemplateId = keccak256("incentive-convex");

    // DEX Template Ids
    bytes32 internal curveRLockedTemplateId = keccak256("dex-curveRebasingLocked");

    // LST/LRT Template Ids
    bytes32 internal oEthLstTemplateId = keccak256("lst-oeth");

    constructor() Calculators(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        _deployTemplates();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        console.log("");

        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

        _deployLsts();

        console.log("");

        _deployCurveConvexCalculators();

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }

    function _deployTemplates() private {
        OethLSTCalculator oEthLstTemplate = new OethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("OETH Template", oEthLstTemplate, oEthLstTemplateId);
    }

    function _deployLsts() private {
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: oEthLstTemplateId, lstTokenAddress: constants.tokens.oEth })
        );
    }

    function _deployCurveConvexCalculators() private {
        bytes32[] memory e = new bytes32[](2);

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.oEth);

        _deployCurveV1RebaseLockedConvexCalculators(
            CurveRebasingConvexSetup({
                name: "ETH/OETH",
                dependentAprIds: e,
                poolAddress: 0x94B17476A93b3262d87B9a326965D1E91f9c13E7,
                lpToken: 0x94B17476A93b3262d87B9a326965D1E91f9c13E7,
                rewarder: 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A, //174
                rebasingTokenIdx: 1
            })
        );
    }

    function _deployCurveV1RebaseLockedConvexCalculators(CurveRebasingConvexSetup memory args) private {
        _deployCurveRebasingConvexCalculators(constants, args, curveRLockedTemplateId, convexTemplateId);
    }

    function registerTemplateAndOutput(string memory name, IStatsCalculator calc, bytes32 id) private {
        constants.sys.statsCalcFactory.registerTemplate(id, address(calc));
        console.log(string.concat(name, ": "), address(calc));
    }
}
