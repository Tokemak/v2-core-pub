// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

contract IncentivePricingRegistration is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, owner);

        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.aero);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.bal);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.aura);

        constants.sys.accessController.revokeRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, owner);

        vm.stopBroadcast();
    }
}
