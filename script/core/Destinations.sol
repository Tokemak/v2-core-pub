// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { Constants } from "../utils/Constants.sol";

import { Calculators } from "script/core/Calculators.sol";
import { Oracle } from "script/core/Oracle.sol";
import { Stats } from "src/stats/Stats.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

contract Destinations is Calculators, Oracle {
    bytes32 internal auraTemplateId = keccak256("incentive-aura");
    bytes32 internal convexTemplateId = keccak256("incentive-convex");
    bytes32 internal balCompTemplateId = keccak256("dex-balComp");
    bytes32 internal balGyroTemplateId = keccak256("dex-balGyro");

    uint256 public saltIx;

    struct CurveConvexSetup {
        string name;
        address curvePool;
        address curveLpToken;
        address convexStaking;
        uint256 convexPoolId;
    }

    struct BalancerAuraSetup {
        string name;
        address balancerPool;
        address auraStaking;
        uint256 auraPoolId;
    }

    struct BalancerSetup {
        string name;
        address balancerPool;
    }

    struct BalancerAuraDestCalcSetup {
        string name;
        address poolAddress;
        bytes32[] dependentPoolCalculators;
        address rewarderAddress;
        uint256 poolId;
    }

    struct BalancerDestCalcSetup {
        string name;
        address poolAddress;
        bytes32[] dependentPoolCalculators;
    }

    constructor(VmSafe _vm) Calculators(_vm) { }

    function setupBalancerGyroAuraDestinationVault(
        Constants.Values memory constants,
        BalancerAuraSetup memory args
    ) internal {
        _setupBalancerAuraDestinationVault(constants, args, "bal-aura-gyro-v1");
    }

    function setupBalancerAuraDestinationVault(
        Constants.Values memory constants,
        BalancerAuraSetup memory args
    ) internal {
        _setupBalancerAuraDestinationVault(constants, args, "bal-aura-v1");
    }

    function _setupBalancerAuraDestinationVault(
        Constants.Values memory constants,
        BalancerAuraSetup memory args,
        string memory destinationTemplateId
    ) private {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: args.balancerPool,
            auraStaking: args.auraStaking,
            auraBooster: constants.ext.auraBooster,
            auraPoolId: args.auraPoolId
        });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                destinationTemplateId,
                constants.tokens.weth,
                initParams.balancerPool,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        keccak256(abi.encode("incentive-v4-", constants.tokens.aura, args.auraStaking))
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Balancer Aura ", args.name, " Dest Vault: "), address(newVault));
    }

    function setupBalancerDestinationVault(Constants.Values memory constants, BalancerSetup memory args) internal {
        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: args.balancerPool });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                "bal-v1",
                constants.tokens.weth,
                initParams.balancerPool,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        Stats.generateBalancerPoolIdentifier(args.balancerPool)
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Balancer ", args.name, " Dest Vault: "), address(newVault));
    }

    function setupCurveNGConvexDestinationVault(
        Constants.Values memory constants,
        CurveConvexSetup memory args
    ) internal {
        setupCurveConvexBaseDestinationVault(constants, args.name, "crv-cvx-ng-v1", args);
    }

    function setupCurveConvexDestinationVault(
        Constants.Values memory constants,
        CurveConvexSetup memory args
    ) internal {
        setupCurveConvexBaseDestinationVault(constants, args.name, "crv-cvx-v1", args);
    }

    function setupCurveConvexBaseDestinationVault(
        Constants.Values memory constants,
        string memory name,
        string memory template,
        CurveConvexSetup memory args
    ) internal {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: args.curvePool,
            convexStaking: args.convexStaking,
            convexPoolId: args.convexPoolId
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                template,
                constants.tokens.weth,
                args.curveLpToken,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        keccak256(abi.encode("incentive-v5-", constants.tokens.cvx, args.convexStaking))
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Curve ", name, " Dest Vault: "), address(newVault));
    }

    function deployBalancerAuraCompStable(
        Constants.Values memory constants,
        BalancerAuraDestCalcSetup memory args
    ) internal {
        IStatsCalculator poolCalc = IStatsCalculator(
            _setupBalancerCalculator(
                constants,
                BalancerCalcSetup({
                    name: args.name,
                    aprTemplateId: balCompTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.balancerComp, args.poolAddress, false
        );

        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: args.name,
                aprTemplateId: auraTemplateId,
                poolCalculator: poolCalc,
                platformToken: constants.tokens.aura,
                rewarder: args.rewarderAddress,
                lpToken: args.poolAddress,
                pool: args.poolAddress
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: args.name,
                balancerPool: args.poolAddress,
                auraStaking: args.rewarderAddress,
                auraPoolId: args.poolId
            })
        );
    }

    function deployBalancerCompStable(Constants.Values memory constants, BalancerDestCalcSetup memory args) internal {
        IStatsCalculator(
            _setupBalancerCalculator(
                constants,
                BalancerCalcSetup({
                    name: args.name,
                    aprTemplateId: balCompTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress
                })
            )
        );
        _registerPoolMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.balancerComp, args.poolAddress, false
        );

        setupBalancerDestinationVault(constants, BalancerSetup({ name: args.name, balancerPool: args.poolAddress }));
    }

    function deployBalancerGyroAura(
        Constants.Values memory constants,
        BalancerAuraDestCalcSetup memory args
    ) internal {
        IStatsCalculator poolCalc = IStatsCalculator(
            _setupBalancerCalculator(
                constants,
                BalancerCalcSetup({
                    name: args.name,
                    aprTemplateId: balGyroTemplateId,
                    dependentAprIds: args.dependentPoolCalculators,
                    poolAddress: args.poolAddress
                })
            )
        );

        _registerPoolMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.balancerComp, args.poolAddress, false
        );

        _setupIncentiveCalculatorBase(
            constants,
            IncentiveCalcBaseSetup({
                name: args.name,
                aprTemplateId: auraTemplateId,
                poolCalculator: poolCalc,
                platformToken: constants.tokens.aura,
                rewarder: args.rewarderAddress,
                lpToken: args.poolAddress,
                pool: args.poolAddress
            })
        );

        setupBalancerGyroAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: args.name,
                balancerPool: args.poolAddress,
                auraStaking: args.rewarderAddress,
                auraPoolId: args.poolId
            })
        );
    }
}
