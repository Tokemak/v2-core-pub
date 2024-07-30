// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Script } from "forge-std/Script.sol";
import { Destinations } from "script/core/Destinations.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

contract DestCalcSet3 is Script, Destinations {
    Constants.Values public constants;

    // LST Template Ids
    bytes32 internal rsEthLrtTemplateId = keccak256("lrt-rsEth");
    bytes32 internal ethXEthLstTemplateId = keccak256("lst-ethX");
    bytes32 internal eEthLstTemplateId = keccak256("lst-eEth");
    bytes32 internal proxyLstTemplateId = keccak256("lst-proxy");

    bytes32 internal curveNRTemplateId = keccak256("dex-curveNoRebasing");
    bytes32 internal balMetaTemplateId = keccak256("dex-balMeta");
    bytes32 internal curveV2NRTemplateId = keccak256("dex-curveV2NoRebasing");

    constructor() Destinations(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        // Setup missing oracles for the tokens/calculators we're deploying
        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        //deployCurvePools();
        deployBalancerPools();
        deployCurvePools();
        //deployCurveConvex();
        //deployBalancerAura();

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    struct CurveRebasingConvexDestCalcSetup {
        string name;
        address poolAddress;
        address lpTokenAddress;
        bytes32 curveTemplateId;
        bytes32[] dependentPoolCalculators;
        address rewarderAddress;
        uint256 poolId;
        uint256 rebasingTokenIndex;
    }

    struct CurveNoRebasingConvexDestCalcSetup {
        string name;
        address poolAddress;
        address lpTokenAddress;
        bytes32 curveTemplateId;
        bytes32[] dependentPoolCalculators;
        address rewarderAddress;
        uint256 poolId;
        bool isNg;
    }

    function deployCurvePools() internal {
        bytes32[] memory e = new bytes32[](2);
        e[0] = keccak256(abi.encode("lst", constants.tokens.wstEth));
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.ethX);

        deployCurveV2NonRebasingPool(
            CurveNoRebasingConvexDestCalcSetup({
                name: "ETHx/wstETH",
                poolAddress: 0x14756A5eD229265F86990e749285bDD39Fe0334F,
                lpTokenAddress: 0xfffAE954601cFF1195a8E20342db7EE66d56436B,
                curveTemplateId: curveV2NRTemplateId,
                dependentPoolCalculators: e,
                rewarderAddress: 0x85b118e0Fa5706d99b270be43d782FBE429aD409,
                poolId: 265,
                isNg: false
            })
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);

        deployCurveV2NonRebasingPool(
            CurveNoRebasingConvexDestCalcSetup({
                name: "WETH/rETH",
                poolAddress: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                lpTokenAddress: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                curveTemplateId: curveNRTemplateId,
                dependentPoolCalculators: e,
                rewarderAddress: 0x2686e9E88AAc7a3B3007CAD5b7a2253438cac6D4,
                poolId: 287,
                isNg: true
            })
        );
    }

    function deployCurveV1NoRebasingPool(CurveNoRebasingConvexDestCalcSetup memory args) internal {
        IStatsCalculator poolCalc = IStatsCalculator(
            _setupCurvePoolNoRebasingCalculatorBase(
                constants,
                CurveNoRebasingSetup({
                    name: args.name,
                    aprTemplateId: args.curveTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress
                })
            )
        );

        _registerPoolMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.curveV1, args.poolAddress, false);

        constants.sys.subOracles.curveV1.registerPool(args.poolAddress, args.lpTokenAddress);

        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: args.name,
                aprTemplateId: convexTemplateId,
                poolCalculator: poolCalc,
                platformToken: constants.tokens.cvx,
                rewarder: args.rewarderAddress,
                lpToken: args.lpTokenAddress,
                pool: args.poolAddress
            })
        );

        if (args.isNg) {
            setupCurveNGConvexDestinationVault(
                constants,
                CurveConvexSetup({
                    name: args.name,
                    curvePool: args.poolAddress,
                    curveLpToken: args.lpTokenAddress,
                    convexStaking: args.rewarderAddress,
                    convexPoolId: args.poolId
                })
            );
        } else {
            setupCurveConvexDestinationVault(
                constants,
                CurveConvexSetup({
                    name: args.name,
                    curvePool: args.poolAddress,
                    curveLpToken: args.lpTokenAddress,
                    convexStaking: args.rewarderAddress,
                    convexPoolId: args.poolId
                })
            );
        }
    }

    function deployCurveV1RebasingPool(CurveRebasingConvexDestCalcSetup memory args) internal {
        IStatsCalculator poolCalc = IStatsCalculator(
            _setupCurvePoolRebasingCalculatorBase(
                constants,
                CurveRebasingSetup({
                    name: args.name,
                    aprTemplateId: args.curveTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress,
                    rebasingTokenIdx: args.rebasingTokenIndex
                })
            )
        );

        _registerPoolMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.curveV1, args.poolAddress, false);

        constants.sys.subOracles.curveV1.registerPool(args.poolAddress, args.lpTokenAddress);

        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: args.name,
                aprTemplateId: convexTemplateId,
                poolCalculator: poolCalc,
                platformToken: constants.tokens.cvx,
                rewarder: args.rewarderAddress,
                lpToken: args.lpTokenAddress,
                pool: args.poolAddress
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: args.name,
                curvePool: args.poolAddress,
                curveLpToken: args.lpTokenAddress,
                convexStaking: args.rewarderAddress,
                convexPoolId: args.poolId
            })
        );
    }

    function deployCurveV2NonRebasingPool(CurveNoRebasingConvexDestCalcSetup memory args) internal {
        IStatsCalculator poolCalc = IStatsCalculator(
            _setupCurvePoolNoRebasingCalculatorBase(
                constants,
                CurveNoRebasingSetup({
                    name: args.name,
                    aprTemplateId: args.curveTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress
                })
            )
        );

        _registerPoolMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.curveV2, args.poolAddress, false);

        constants.sys.subOracles.curveV2.registerPool(args.poolAddress, args.lpTokenAddress);

        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: args.name,
                aprTemplateId: convexTemplateId,
                poolCalculator: poolCalc,
                platformToken: constants.tokens.cvx,
                rewarder: args.rewarderAddress,
                lpToken: args.lpTokenAddress,
                pool: args.poolAddress
            })
        );

        if (args.isNg) {
            setupCurveNGConvexDestinationVault(
                constants,
                CurveConvexSetup({
                    name: args.name,
                    curvePool: args.poolAddress,
                    curveLpToken: args.lpTokenAddress,
                    convexStaking: args.rewarderAddress,
                    convexPoolId: args.poolId
                })
            );
        } else {
            setupCurveConvexDestinationVault(
                constants,
                CurveConvexSetup({
                    name: args.name,
                    curvePool: args.poolAddress,
                    curveLpToken: args.lpTokenAddress,
                    convexStaking: args.rewarderAddress,
                    convexPoolId: args.poolId
                })
            );
        }
    }

    function deployBalancerPools() internal {
        bytes32[] memory depLstsCalcs = new bytes32[](2);
        depLstsCalcs[0] = Stats.NOOP_APR_ID;
        depLstsCalcs[1] = Stats.generateRawTokenIdentifier(constants.tokens.osEth);

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "osETH/WETH",
                poolAddress: 0xDACf5Fa19b1f720111609043ac67A9818262850c,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x5F032f15B4e910252EDaDdB899f7201E89C8cD6b,
                poolId: 179
            })
        );

        depLstsCalcs[0] = keccak256(abi.encode("lst", constants.tokens.wstEth));
        depLstsCalcs[1] = Stats.NOOP_APR_ID;

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "wstETH/WETH",
                poolAddress: 0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x2a14dB8D09dB0542f6A371c0cB308A768227D67D,
                poolId: 153
            })
        );

        depLstsCalcs[0] = keccak256(abi.encode("lst", constants.tokens.wstEth));
        depLstsCalcs[1] = Stats.generateRawTokenIdentifier(constants.tokens.ethX);

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "ETHx/wstETH",
                poolAddress: 0xB91159aa527D4769CB9FAf3e4ADB760c7E8C8Ea7,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x571a20C14a7c3Ac6d30Ee7D1925940bb0C027696,
                poolId: 207
            })
        );

        depLstsCalcs[0] = Stats.NOOP_APR_ID;
        depLstsCalcs[1] = Stats.generateRawTokenIdentifier(constants.tokens.swEth);

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "swETH/WETH",
                poolAddress: 0xE7e2c68d3b13d905BBb636709cF4DfD21076b9D2,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0xf8f18dc9E192A9Bf9347DA0E2107d05D5B67F38e,
                poolId: 152
            })
        );
    }
}
