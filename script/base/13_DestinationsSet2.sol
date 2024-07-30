// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Destinations } from "script/core/Destinations.sol";

contract DestinationsSet2 is Script, Destinations {
    Constants.Values public constants;

    constructor() Destinations(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        setupDestinations();

        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function setupDestinations() internal {
        setupBalancerDestinations();
    }

    function setupBalancerDestinations() internal {
        bytes32[] memory depLstsCalcs = new bytes32[](2);
        depLstsCalcs[0] = Stats.generateRawTokenIdentifier(constants.tokens.weEth);
        depLstsCalcs[1] = Stats.NOOP_APR_ID;

        deployBalancerAuraCompStable(
            constants,
            BalancerAuraDestCalcSetup({
                name: "weETH/WETH",
                poolAddress: 0xaB99a3e856dEb448eD99713dfce62F937E2d4D74,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x26E72914767ba0bb27350Fa485A3698475072BBa,
                poolId: 9
            })
        );
    }
}
