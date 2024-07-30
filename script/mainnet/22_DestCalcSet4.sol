// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Script } from "forge-std/Script.sol";
import { Destinations } from "script/core/Destinations.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { RswethLRTCalculator } from "src/stats/calculators/RswethLRTCalculator.sol";
import { EzethLRTCalculator } from "src/stats/calculators/EzethLRTCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { console } from "forge-std/console.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";

contract DestCalcSet4 is Script, Destinations {
    Constants.Values public constants;

    // LST Template Ids
    bytes32 internal rswEthLrtTemplateId = keccak256("lrt-rswEth");
    bytes32 internal ezEthLrtTemplateId = keccak256("lrt-ezEth");

    constructor() Destinations(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        // Setup missing oracles for the tokens/calculators we're deploying
        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.rswEth,
                feedAddress: 0x3A236F67Fce401D87D7215695235e201966576E4,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.ezEth,
                feedAddress: 0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 12 hours,
                safePriceThreshold: 200
            })
        );

        registerAndOutput(
            constants,
            "rswETH LRT Calculator",
            new RswethLRTCalculator(constants.sys.systemRegistry),
            rswEthLrtTemplateId
        );
        registerAndOutput(
            constants, "ezETH LRT Calculator", new EzethLRTCalculator(constants.sys.systemRegistry), ezEthLrtTemplateId
        );

        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: rswEthLrtTemplateId, lstTokenAddress: constants.tokens.rswEth })
        );

        // Setup ezETH Calculator
        LSTCalculatorBase.InitData memory initData =
            LSTCalculatorBase.InitData({ lstTokenAddress: constants.tokens.ezEth });
        bytes32[] memory e = new bytes32[](0);

        EzethLRTCalculator.EzEthInitData memory ezEthInitData = EzethLRTCalculator.EzEthInitData({
            restakeManager: 0x74a09653A083691711cF8215a6ab074BB4e99ef5,
            baseInitData: abi.encode(initData)
        });

        address addr = constants.sys.statsCalcFactory.create(ezEthLrtTemplateId, e, abi.encode(ezEthInitData));
        console.log("");
        console.log("ezETH LST Calculator address: ", addr);
        console.log(
            string.concat("ezETH Last Snapshot Timestamp: "), EzethLRTCalculator(addr).current().lastSnapshotTimestamp
        );
        console.log("");

        bytes32[] memory depLstsCalcs = new bytes32[](2);
        depLstsCalcs[0] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);
        depLstsCalcs[1] = keccak256(abi.encode("lst", constants.tokens.weEth));

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "weETH/rETH",
                poolAddress: 0x05ff47AFADa98a98982113758878F9A8B9FddA0a,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x07A319A023859BbD49CC9C38ee891c3EA9283Cc5,
                poolId: 182
            })
        );

        depLstsCalcs[0] = Stats.NOOP_APR_ID;
        depLstsCalcs[1] = keccak256(abi.encode("lst", constants.tokens.weEth));

        deployBalancerCompStable(
            constants,
            BalancerDestCalcSetup({
                name: "WETH/weETH",
                poolAddress: 0xb9dEbDDF1d894c79D2B2d09f819FF9B856FCa552,
                dependentPoolCalculators: depLstsCalcs
            })
        );

        depLstsCalcs[0] = Stats.generateRawTokenIdentifier(constants.tokens.ezEth);
        depLstsCalcs[1] = Stats.NOOP_APR_ID;

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "ezETH/WETH",
                poolAddress: 0x596192bB6e41802428Ac943D2f1476C1Af25CC0E,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x95eC73Baa0eCF8159b4EE897D973E41f51978E50,
                poolId: 189
            })
        );

        depLstsCalcs = new bytes32[](3);
        depLstsCalcs[0] = Stats.generateRawTokenIdentifier(constants.tokens.ezEth);
        depLstsCalcs[1] = keccak256(abi.encode("lst", constants.tokens.weEth));
        depLstsCalcs[2] = Stats.generateRawTokenIdentifier(constants.tokens.rswEth);

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "ezETH/weETH/rswETH",
                poolAddress: 0x848a5564158d84b8A8fb68ab5D004Fae11619A54,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0xce98eb8b2Fb98049b3F2dB0A212Ba7ca3Efd63b0,
                poolId: 198
            })
        );

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        vm.stopBroadcast();
    }
}
