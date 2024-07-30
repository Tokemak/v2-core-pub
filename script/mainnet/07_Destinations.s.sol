// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Destinations as DestinationFns } from "script/core/Destinations.sol";

contract Destinations is Script, DestinationFns {
    Constants.Values public constants;

    constructor() DestinationFns(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        setupDestinations();

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function setupDestinations() internal {
        setupCurveDestinations();
        setupBalancerDestinations();
    }

    function setupCurveDestinations() internal {
        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "stETH/ETH Original",
                curvePool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                curveLpToken: 0x06325440D014e39736583c165C2963BA99fAf14E,
                convexStaking: 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
                convexPoolId: 25
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "stETH/ETH NG",
                curvePool: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
                curveLpToken: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
                convexStaking: 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
                convexPoolId: 177
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "cbETH/ETH",
                curvePool: 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A,
                curveLpToken: 0x5b6C539b224014A09B3388e51CaAA8e354c959C8,
                convexStaking: 0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699,
                convexPoolId: 127
            })
        );

        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "osETH/rETH",
                curvePool: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                curveLpToken: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                convexStaking: 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e,
                convexPoolId: 268
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "rETH/wstETH",
                curvePool: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
                curveLpToken: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
                convexStaking: 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc,
                convexPoolId: 73
            })
        );
    }

    function setupBalancerDestinations() internal {
        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "wstETH/WETH",
                balancerPool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
                auraStaking: 0x59D66C58E83A26d6a0E35114323f65c3945c89c1,
                auraPoolId: 115
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "rETH/WETH",
                balancerPool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
                auraStaking: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
                auraPoolId: 109
            })
        );
    }
}
