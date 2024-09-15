// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { AuraCalculator } from "src/stats/calculators/AuraCalculator.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";
import { BalancerComposableStablePoolCalculator } from
    "src/stats/calculators/BalancerComposableStablePoolCalculator.sol";
import { BalancerGyroPoolCalculator } from "src/stats/calculators/BalancerGyroPoolCalculator.sol";
import { BalancerMetaStablePoolCalculator } from "src/stats/calculators/BalancerMetaStablePoolCalculator.sol";
import { CurveV1PoolNoRebasingStatsCalculator } from "src/stats/calculators/CurveV1PoolNoRebasingStatsCalculator.sol";
import { CurveV1PoolRebasingStatsCalculator } from "src/stats/calculators/CurveV1PoolRebasingStatsCalculator.sol";
import { CurveV1PoolRebasingLockedStatsCalculator } from
    "src/stats/calculators/CurveV1PoolRebasingLockedStatsCalculator.sol";
import { CurveV2PoolNoRebasingStatsCalculator } from "src/stats/calculators/CurveV2PoolNoRebasingStatsCalculator.sol";

import { CbethLSTCalculator } from "src/stats/calculators/CbethLSTCalculator.sol";
import { RethLSTCalculator } from "src/stats/calculators/RethLSTCalculator.sol";
import { StethLSTCalculator } from "src/stats/calculators/StethLSTCalculator.sol";
import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";
import { OsethLSTCalculator } from "src/stats/calculators/OsethLSTCalculator.sol";
import { SwethLSTCalculator } from "src/stats/calculators/SwethLSTCalculator.sol";
import { FrxEthLSTCalculator } from "src/stats/calculators/FrxEthLSTCalculator.sol";

import { RsethLRTCalculator } from "src/stats/calculators/RsethLRTCalculator.sol";
import { ETHxLSTCalculator } from "src/stats/calculators/ETHxLSTCalculator.sol";
import { EethLSTCalculator } from "src/stats/calculators/EethLSTCalculator.sol";
import { EzethLRTCalculator } from "src/stats/calculators/EzethLRTCalculator.sol";
import { PxEthLSTCalculator } from "src/stats/calculators/PxEthLSTCalculator.sol";
import { RswethLRTCalculator } from "src/stats/calculators/RswethLRTCalculator.sol";

import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { Stats } from "src/stats/Stats.sol";
import { Calculators } from "script/core/Calculators.sol";

contract CalculatorsDeploy is Script, Calculators {
    Constants.Values public constants;

    // Incentive Template Ids
    bytes32 internal auraTemplateId = keccak256("incentive-aura");
    bytes32 internal convexTemplateId = keccak256("incentive-convex");

    // DEX Template Ids
    bytes32 internal balCompTemplateId = keccak256("dex-balComp");
    bytes32 internal balGyroTemplateId = keccak256("dex-balGyro");
    bytes32 internal balMetaTemplateId = keccak256("dex-balMeta");
    bytes32 internal curveNRTemplateId = keccak256("dex-curveNoRebasing");
    bytes32 internal curveRLockedTemplateId = keccak256("dex-curveRebasingLocked");
    bytes32 internal curveRTemplateId = keccak256("dex-curveRebasing");
    bytes32 internal curveV2NRTemplateId = keccak256("dex-curveV2NoRebasing");

    // LST/LRT Template Ids
    bytes32 internal cbEthLstTemplateId = keccak256("lst-cbeth");
    bytes32 internal eEthLstTemplateId = keccak256("lst-eeth");
    bytes32 internal ethXLstTemplateId = keccak256("lst-ethx");
    bytes32 internal ezEthLrtTemplateId = keccak256("lrt-ezeth");
    bytes32 internal frxEthLstTemplateId = keccak256("lst-frxeth");
    bytes32 internal osEthLstTemplateId = keccak256("lst-oseth");
    bytes32 internal proxyLstTemplateId = keccak256("lst-proxy");
    bytes32 internal pxEthLstTemplateId = keccak256("lst-pxeth");
    bytes32 internal rEthLstTemplateId = keccak256("lst-reth");
    bytes32 internal rsEthLrtTemplateId = keccak256("lrt-rseth");
    bytes32 internal rswEthLrtTemplateId = keccak256("lrt-rsweth");
    bytes32 internal stEthLstTemplateId = keccak256("lst-steth");
    bytes32 internal swethLstTemplateId = keccak256("lst-sweth");

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

        _deployBalancerAuraCalculators();

        console.log("");

        _deployCurveConvexCalculators();

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }

    function _deployTemplates() private {
        AuraCalculator auraTemplate = new AuraCalculator(constants.sys.systemRegistry, constants.ext.auraBooster);
        registerTemplateAndOutput("Aura Template", auraTemplate, auraTemplateId);

        BalancerComposableStablePoolCalculator balCompTemplate = new BalancerComposableStablePoolCalculator(
            constants.sys.systemRegistry, address(constants.ext.balancerVault)
        );
        registerTemplateAndOutput("Balancer Comp Template", balCompTemplate, balCompTemplateId);

        BalancerGyroPoolCalculator balGyroTemplate =
            new BalancerGyroPoolCalculator(constants.sys.systemRegistry, address(constants.ext.balancerVault));
        registerTemplateAndOutput("Balancer Gyro Template", balGyroTemplate, balGyroTemplateId);

        BalancerMetaStablePoolCalculator balMetaTemplate =
            new BalancerMetaStablePoolCalculator(constants.sys.systemRegistry, address(constants.ext.balancerVault));
        registerTemplateAndOutput("Balancer Meta Template", balMetaTemplate, balMetaTemplateId);

        CbethLSTCalculator cbEthLstTemplate = new CbethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("cbETH Template", cbEthLstTemplate, cbEthLstTemplateId);

        ConvexCalculator convexTemplate =
            new ConvexCalculator(constants.sys.systemRegistry, constants.ext.convexBooster);
        registerTemplateAndOutput("Convex Template", convexTemplate, convexTemplateId);

        CurveV1PoolNoRebasingStatsCalculator curveNRTemplate =
            new CurveV1PoolNoRebasingStatsCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("Curve V1 No Rebasing Template", curveNRTemplate, curveNRTemplateId);

        CurveV1PoolRebasingLockedStatsCalculator curveRLockedTemplate =
            new CurveV1PoolRebasingLockedStatsCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("Curve V1 Rebasing Locked Template", curveRLockedTemplate, curveRLockedTemplateId);

        CurveV1PoolRebasingStatsCalculator curveRTemplate =
            new CurveV1PoolRebasingStatsCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("Curve V1 Rebasing Template", curveRTemplate, curveRTemplateId);

        CurveV2PoolNoRebasingStatsCalculator curveV2NRTemplate =
            new CurveV2PoolNoRebasingStatsCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("Curve V2 No Rebasing Template", curveV2NRTemplate, curveV2NRTemplateId);

        EethLSTCalculator eEthLstTemplate = new EethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("eETH Template", eEthLstTemplate, eEthLstTemplateId);

        ETHxLSTCalculator ethXLstTemplate = new ETHxLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("ETHx Template", ethXLstTemplate, ethXLstTemplateId);

        EzethLRTCalculator ezEthLrtTemplate = new EzethLRTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("ezETH Template", ezEthLrtTemplate, ezEthLrtTemplateId);

        FrxEthLSTCalculator frxEthLstTemplate = new FrxEthLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("frxETH Template", frxEthLstTemplate, frxEthLstTemplateId);

        OsethLSTCalculator osEthLstTemplate = new OsethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("osETH Template", osEthLstTemplate, osEthLstTemplateId);

        ProxyLSTCalculator proxyLstTemplate = new ProxyLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("Proxy Template", proxyLstTemplate, proxyLstTemplateId);

        PxEthLSTCalculator pxEthLstTemplate = new PxEthLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("pxETH Template", pxEthLstTemplate, pxEthLstTemplateId);

        RethLSTCalculator rEthLstTemplate = new RethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("rETH Template", rEthLstTemplate, rEthLstTemplateId);

        RsethLRTCalculator rsEthLrtTemplate = new RsethLRTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("rsETH LRT Template", rsEthLrtTemplate, rsEthLrtTemplateId);

        RswethLRTCalculator rswEthLrtTemplate = new RswethLRTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("rswETH LRT Template", rswEthLrtTemplate, rswEthLrtTemplateId);

        StethLSTCalculator stEthLstTemplate = new StethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("stETH LST Template", stEthLstTemplate, stEthLstTemplateId);

        SwethLSTCalculator swethLstTemplate = new SwethLSTCalculator(constants.sys.systemRegistry);
        registerTemplateAndOutput("swETH Template", swethLstTemplate, swethLstTemplateId);
    }

    function _deployLsts() private {
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: cbEthLstTemplateId, lstTokenAddress: constants.tokens.cbEth })
        );
        address eEthLstCalculator = _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: eEthLstTemplateId, lstTokenAddress: constants.tokens.eEth })
        );
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: ethXLstTemplateId, lstTokenAddress: constants.tokens.ethX })
        );
        _setupEzEthCalculator(constants, 0x74a09653A083691711cF8215a6ab074BB4e99ef5, ezEthLrtTemplateId);
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: frxEthLstTemplateId, lstTokenAddress: constants.tokens.frxEth })
        );
        _setupOsEthLSTCalculator(constants, osEthLstTemplateId);
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: pxEthLstTemplateId, lstTokenAddress: constants.tokens.pxEth })
        );
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: rEthLstTemplateId, lstTokenAddress: constants.tokens.rEth })
        );
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: rsEthLrtTemplateId, lstTokenAddress: constants.tokens.rsEth })
        );
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: rswEthLrtTemplateId, lstTokenAddress: constants.tokens.rswEth })
        );
        address stEthLstCalculator = _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: stEthLstTemplateId, lstTokenAddress: constants.tokens.stEth })
        );
        _setupLSTCalculatorBase(
            constants, LSTCalcSetup({ aprTemplateId: swethLstTemplateId, lstTokenAddress: constants.tokens.swEth })
        );
        _setupProxyLSTCalculator(
            constants,
            ProxyLstCalculatorSetup({
                name: "weETH",
                aprTemplateId: proxyLstTemplateId,
                lstTokenAddress: constants.tokens.weEth,
                statsCalculator: eEthLstCalculator,
                usePriceAsDiscount: false
            })
        );
        _setupProxyLSTCalculator(
            constants,
            ProxyLstCalculatorSetup({
                name: "wstETH",
                aprTemplateId: proxyLstTemplateId,
                lstTokenAddress: constants.tokens.wstEth,
                statsCalculator: stEthLstCalculator,
                usePriceAsDiscount: false
            })
        );
    }

    function _deployBalancerAuraCalculators() private {
        bytes32[] memory e = new bytes32[](2);

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerMetaAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "rETH/WETH",
                poolAddress: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
                dependentPoolCalculators: e,
                rewarderAddress: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
                poolId: 109
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.osEth);

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "WETH/osETH",
                poolAddress: 0xDACf5Fa19b1f720111609043ac67A9818262850c,
                dependentPoolCalculators: e,
                rewarderAddress: 0x5F032f15B4e910252EDaDdB899f7201E89C8cD6b,
                poolId: 179
            })
        );

        e[0] = Stats.generateProxyIdentifier(constants.tokens.wstEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "wstETH/WETH",
                poolAddress: 0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD,
                dependentPoolCalculators: e,
                rewarderAddress: 0x2a14dB8D09dB0542f6A371c0cB308A768227D67D,
                poolId: 153
            })
        );

        e[0] = Stats.generateProxyIdentifier(constants.tokens.wstEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerGyroAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "wstETH/WETH (Gyro)",
                poolAddress: 0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1,
                dependentPoolCalculators: e,
                rewarderAddress: 0x35113146E7f2dF77Fb40606774e0a3F402035Ffb,
                poolId: 162
            })
        );

        e[0] = Stats.generateProxyIdentifier(constants.tokens.wstEth);
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.cbEth);

        _deployBalancerGyroAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "wstETH/cbETH (Gyro)",
                poolAddress: 0xF7A826D47c8E02835D94fb0Aa40F0cC9505cb134,
                dependentPoolCalculators: e,
                rewarderAddress: 0xC2E2D76a5e02eA65Ecd3be6c9cd3Fa29022f4548,
                poolId: 161
            })
        );

        e[0] = Stats.generateProxyIdentifier(constants.tokens.wstEth);
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.ethX);

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "wstETH/ETHx",
                poolAddress: 0xB91159aa527D4769CB9FAf3e4ADB760c7E8C8Ea7,
                dependentPoolCalculators: e,
                rewarderAddress: 0x571a20C14a7c3Ac6d30Ee7D1925940bb0C027696,
                poolId: 207
            })
        );

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.pxEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "pxETH/WETH",
                poolAddress: 0x88794C65550DeB6b4087B7552eCf295113794410,
                dependentPoolCalculators: e,
                rewarderAddress: 0x570eA5C8A528E3495EE9883910012BeD598E8814,
                poolId: 185
            })
        );

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.ezEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "ezETH/WETH",
                poolAddress: 0x596192bB6e41802428Ac943D2f1476C1Af25CC0E,
                dependentPoolCalculators: e,
                rewarderAddress: 0x95eC73Baa0eCF8159b4EE897D973E41f51978E50,
                poolId: 189
            })
        );

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);
        e[1] = Stats.generateProxyIdentifier(constants.tokens.weEth);

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "rETH/weETH",
                poolAddress: 0x05ff47AFADa98a98982113758878F9A8B9FddA0a,
                dependentPoolCalculators: e,
                rewarderAddress: 0x07A319A023859BbD49CC9C38ee891c3EA9283Cc5,
                poolId: 182
            })
        );

        e = new bytes32[](3);
        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.ezEth);
        e[1] = Stats.generateProxyIdentifier(constants.tokens.weEth);
        e[2] = Stats.generateRawTokenIdentifier(constants.tokens.rswEth);

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "ezETH/weETH/rswETH",
                poolAddress: 0x848a5564158d84b8A8fb68ab5D004Fae11619A54,
                dependentPoolCalculators: e,
                rewarderAddress: 0xce98eb8b2Fb98049b3F2dB0A212Ba7ca3Efd63b0,
                poolId: 198
            })
        );

        e = new bytes32[](2);
        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.rsEth);
        e[1] = Stats.NOOP_APR_ID;

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "rsETH/WETH",
                poolAddress: 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D,
                dependentPoolCalculators: e,
                rewarderAddress: 0xB5FdB4f75C26798A62302ee4959E4281667557E0,
                poolId: 221
            })
        );

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.rsEth);
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.ethX);

        _deployBalancerCompAuraCalc(
            BalancerAuraDestCalcSetup({
                name: "rsETH/ETHx",
                poolAddress: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE,
                dependentPoolCalculators: e,
                rewarderAddress: 0xf618102462Ff3cf7edbA4c067316F1C3AbdbA193,
                poolId: 191
            })
        );
    }

    function _deployCurveConvexCalculators() private {
        bytes32[] memory e = new bytes32[](2);

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.osEth);
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "osETH/rETH",
                dependentAprIds: e,
                poolAddress: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                lpToken: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                rewarder: 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.ethX);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "ETH/ETHx",
                dependentAprIds: e,
                poolAddress: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                lpToken: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                rewarder: 0x399e111c7209a741B06F8F86Ef0Fdd88fC198D20
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "WETH/rETH",
                dependentAprIds: e,
                poolAddress: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                lpToken: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                rewarder: 0x2686e9E88AAc7a3B3007CAD5b7a2253438cac6D4
            })
        );

        e[0] = Stats.generateRawTokenIdentifier(constants.tokens.pxEth);
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.stEth);

        _deployCurveV1RebaseLockedConvexCalculators(
            CurveRebasingConvexSetup({
                name: "pxETH/stETH",
                dependentAprIds: e,
                poolAddress: 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6,
                lpToken: 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6,
                rewarder: 0x633556C8413FCFd45D83656290fF8d64EE41A7c1,
                rebasingTokenIdx: 1
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.pxEth);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "WETH/pxETH",
                dependentAprIds: e,
                poolAddress: 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
                lpToken: 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
                rewarder: 0x3B793E505A3C7dbCb718Fe871De8eBEf7854e74b
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.frxEth);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "WETH/frxETH",
                dependentAprIds: e,
                poolAddress: 0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc,
                lpToken: 0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc,
                rewarder: 0xFafDE12dC476C4913e29F47B4747860C148c5E4f
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateProxyIdentifier(constants.tokens.weEth);

        _deployCurveV1NoRebaseConvexCalculators(
            CurveNoRebasingConvexSetup({
                name: "WETH/weETH-ng",
                dependentAprIds: e,
                poolAddress: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                lpToken: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                rewarder: 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58
            })
        );
    }

    function _deployCurveV1NoRebaseConvexCalculators(CurveNoRebasingConvexSetup memory args) private {
        _deployCurveNoRebasingConvexCalculators(constants, args, curveNRTemplateId, convexTemplateId);
    }

    function _deployCurveV1RebaseLockedConvexCalculators(CurveRebasingConvexSetup memory args) private {
        _deployCurveRebasingConvexCalculators(constants, args, curveRLockedTemplateId, convexTemplateId);
    }

    function _deployBalancerMetaAuraCalc(BalancerAuraDestCalcSetup memory args) private {
        _deployBalancerMetaStableAuraCalculators(constants, args, balMetaTemplateId, auraTemplateId);
    }

    function _deployBalancerCompAuraCalc(BalancerAuraDestCalcSetup memory args) private {
        _deployBalancerCompStableAuraCalculators(constants, args, balCompTemplateId, auraTemplateId);
    }

    function _deployBalancerGyroAuraCalc(BalancerAuraDestCalcSetup memory args) private {
        _deployBalancerGyroAuraCalculators(constants, args, balGyroTemplateId, auraTemplateId);
    }

    function registerTemplateAndOutput(string memory name, IStatsCalculator calc, bytes32 id) private {
        constants.sys.statsCalcFactory.registerTemplate(id, address(calc));
        console.log(string.concat(name, ": "), address(calc));
    }
}
