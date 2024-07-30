// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

import { RsethLRTCalculator } from "src/stats/calculators/RsethLRTCalculator.sol";
import { ETHxLSTCalculator } from "src/stats/calculators/ETHxLSTCalculator.sol";
import { EethLSTCalculator } from "src/stats/calculators/EethLSTCalculator.sol";

import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { Stats } from "src/stats/Stats.sol";
import { Oracle } from "script/core/Oracle.sol";

import { EethOracle } from "src/oracles/providers/EethOracle.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { Calculators } from "script/core/Calculators.sol";

contract CalculatorSet2 is Script, Oracle, Calculators {
    Constants.Values public constants;

    bytes32 internal auraTemplateId = keccak256("incentive-aura");
    bytes32 internal convexTemplateId = keccak256("incentive-convex");

    // LST Template Ids
    bytes32 internal rsEthLrtTemplateId = keccak256("lrt-rsEth");
    bytes32 internal ethXEthLstTemplateId = keccak256("lst-ethX");
    bytes32 internal eEthLstTemplateId = keccak256("lst-eEth");
    bytes32 internal proxyLstTemplateId = keccak256("lst-proxy");

    bytes32 internal curveNRTemplateId = keccak256("dex-curveNoRebasing");
    bytes32 internal balCompTemplateId = keccak256("dex-balComp");
    bytes32 internal balMetaTemplateId = keccak256("dex-balMeta");

    // LST Templates
    RsethLRTCalculator public rsEthLrtTemplate;
    ETHxLSTCalculator public ethXEthLstTemplate;
    EethLSTCalculator public eEthLstTemplate;

    // LST Calculators
    IStatsCalculator public rsEthLrtCalculator;
    IStatsCalculator public ethXLstCalculator;
    IStatsCalculator public eEthLstCalculator;
    IStatsCalculator public weEthLstCalculator;

    // DEX Calculators
    IStatsCalculator public curveEthxEthDexCalculator;
    IStatsCalculator public curveWeEthWETHDexCalculator;
    IStatsCalculator public balancerRsEthWethDexCalculator;
    IStatsCalculator public balancerRsEthEthXDexCalculator;

    EethOracle public eEthOracle;
    BalancerLPComposableStableEthOracle public balCompStableOracle;

    constructor() Calculators(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        eEthOracle = new EethOracle(constants.sys.systemRegistry, constants.tokens.weEth);
        console.log("Eeth Oracle: ", address(eEthOracle));

        balCompStableOracle =
            new BalancerLPComposableStableEthOracle(constants.sys.systemRegistry, constants.ext.balancerVault);
        console.log("Bal Comp Stable Oracle: ", address(balCompStableOracle));

        // Setup missing oracles for the tokens/calculators we're deploying
        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        setupTokenOracles();

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        deployTemplates();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        deployLsts();
        deployCurvePools();
        deployBalancerPools();
        deployCurveConvex();
        deployBalancerAura();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }

    function setupTokenOracles() private {
        constants.sys.subOracles.redStone.registerOracle(
            constants.tokens.rsEth,
            IAggregatorV3Interface(0xA736eAe8805dDeFFba40cAB8c99bCB309dEaBd9B),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        constants.sys.subOracles.redStone.registerOracle(
            constants.tokens.ethX,
            IAggregatorV3Interface(0xc799194cAa24E2874Efa89b4Bf5c92a530B047FF),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        constants.sys.subOracles.redStone.registerOracle(
            constants.tokens.weEth,
            IAggregatorV3Interface(0x8751F736E94F6CD167e8C5B97E245680FbD9CC36),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        _registerMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.redStone, constants.tokens.rsEth, false
        );
        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.redStone, constants.tokens.ethX, false);
        _registerMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.redStone, constants.tokens.weEth, false
        );
        _registerMapping(constants.sys.rootPriceOracle, eEthOracle, constants.tokens.eEth, false);
    }

    function deployTemplates() private {
        // LST Templates

        rsEthLrtTemplate = new RsethLRTCalculator(constants.sys.systemRegistry);
        registerAndOutput(constants, "rsETH LRT Template", rsEthLrtTemplate, rsEthLrtTemplateId);

        ethXEthLstTemplate = new ETHxLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput(constants, "ETHx LST Template", ethXEthLstTemplate, ethXEthLstTemplateId);

        eEthLstTemplate = new EethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput(constants, "eETH LST Template", eEthLstTemplate, eEthLstTemplateId);
    }

    function deployLsts() internal {
        rsEthLrtCalculator = IStatsCalculator(
            _setupLSTCalculatorBase(
                constants, LSTCalcSetup({ aprTemplateId: rsEthLrtTemplateId, lstTokenAddress: constants.tokens.rsEth })
            )
        );
        ethXLstCalculator = IStatsCalculator(
            _setupLSTCalculatorBase(
                constants, LSTCalcSetup({ aprTemplateId: ethXEthLstTemplateId, lstTokenAddress: constants.tokens.ethX })
            )
        );

        eEthLstCalculator = IStatsCalculator(
            _setupLSTCalculatorBase(
                constants, LSTCalcSetup({ aprTemplateId: eEthLstTemplateId, lstTokenAddress: constants.tokens.eEth })
            )
        );
        weEthLstCalculator = IStatsCalculator(
            _setupProxyLSTCalculator(
                constants,
                ProxyLstCalculatorSetup({
                    name: "weEth",
                    aprTemplateId: proxyLstTemplateId,
                    lstTokenAddress: constants.tokens.weEth,
                    statsCalculator: address(eEthLstCalculator),
                    isRebasing: false
                })
            )
        );

        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.rsEth, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.ethX, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.eEth, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.weEth, 200);
    }

    function deployCurvePools() internal {
        bytes32[] memory e = new bytes32[](2);
        e[0] = Stats.NOOP_APR_ID;
        e[1] = ethXLstCalculator.getAprId();

        curveEthxEthDexCalculator = IStatsCalculator(
            _setupCurvePoolRebasingCalculatorBase(
                constants,
                CurveRebasingSetup({
                    name: "Curve ETH/ETHx",
                    aprTemplateId: curveNRTemplateId,
                    dependentAprIds: e,
                    poolAddress: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                    rebasingTokenIdx: 1
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle,
            constants.sys.subOracles.curveV1,
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
            false
        );
        constants.sys.subOracles.curveV1.registerPool(
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492, 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = weEthLstCalculator.getAprId();

        curveWeEthWETHDexCalculator = IStatsCalculator(
            _setupCurvePoolRebasingCalculatorBase(
                constants,
                CurveRebasingSetup({
                    name: "Curve ETH/weETH-ng",
                    aprTemplateId: curveNRTemplateId,
                    dependentAprIds: e,
                    poolAddress: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                    rebasingTokenIdx: 1
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle,
            constants.sys.subOracles.curveV1,
            0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
            false
        );
        constants.sys.subOracles.curveV1.registerPool(
            0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5, 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5
        );
    }

    function deployBalancerPools() internal {
        bytes32[] memory e = new bytes32[](2);

        e[0] = rsEthLrtCalculator.getAprId();
        e[1] = Stats.NOOP_APR_ID;
        balancerRsEthWethDexCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                constants,
                BalancerCalcSetup({
                    name: "Balancer rsETH/WETH Pool",
                    aprTemplateId: balCompTemplateId,
                    dependentAprIds: e,
                    poolAddress: 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle, balCompStableOracle, 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D, false
        );

        e[0] = rsEthLrtCalculator.getAprId();
        e[1] = ethXLstCalculator.getAprId();
        balancerRsEthEthXDexCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                constants,
                BalancerCalcSetup({
                    name: "Balancer rsETH/ETHx Pool",
                    aprTemplateId: balCompTemplateId,
                    dependentAprIds: e,
                    poolAddress: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle, balCompStableOracle, 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE, false
        );
    }

    function deployBalancerAura() internal {
        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: "Aura + Balancer rsETH/ETHx Pool",
                aprTemplateId: auraTemplateId,
                poolCalculator: balancerRsEthEthXDexCalculator,
                platformToken: constants.tokens.aura,
                rewarder: 0xf618102462Ff3cf7edbA4c067316F1C3AbdbA193,
                lpToken: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE,
                pool: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE
            })
        );
    }

    function deployCurveConvex() internal {
        // Curve ETH/ETHx
        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: "Convex + Curve ETH/ETHx",
                aprTemplateId: convexTemplateId,
                poolCalculator: curveEthxEthDexCalculator,
                platformToken: constants.tokens.cvx,
                rewarder: 0x399e111c7209a741B06F8F86Ef0Fdd88fC198D20,
                lpToken: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                pool: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492
            })
        );

        // Curve WETH/weETH
        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: "Convex + Curve WETH/weETH",
                aprTemplateId: convexTemplateId,
                poolCalculator: curveWeEthWETHDexCalculator,
                platformToken: constants.tokens.cvx,
                rewarder: 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58,
                lpToken: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5
            })
        );
    }
}
