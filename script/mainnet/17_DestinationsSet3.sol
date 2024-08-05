// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Destinations } from "script/core/Destinations.sol";

contract CalcsAndDestSet3 is Script, Destinations {
    Constants.Values public constants;

    constructor() Destinations(vm) { }

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
                name: "Convex + Curve ETH/ETHx",
                curvePool: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                curveLpToken: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                convexStaking: 0x399e111c7209a741B06F8F86Ef0Fdd88fC198D20,
                convexPoolId: 232
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "Convex + Curve WETH/weETH",
                curvePool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                curveLpToken: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                convexStaking: 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58,
                convexPoolId: 355
            })
        );
    }

    function setupBalancerDestinations() internal {
        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "Aura + Balancer rsETH/ETHx Pool",
                balancerPool: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE,
                auraStaking: 0xf618102462Ff3cf7edbA4c067316F1C3AbdbA193,
                auraPoolId: 191
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "Balancer rsETH/WETH Pool",
                balancerPool: 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D,
                auraStaking: 0xB5FdB4f75C26798A62302ee4959E4281667557E0,
                auraPoolId: 221
            })
        );
    }
}
