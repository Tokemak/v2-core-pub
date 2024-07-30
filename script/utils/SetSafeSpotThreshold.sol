// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count,no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

contract SetSafeSpotThreshold is Script {
    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        values.sys.rootPriceOracle.setSafeSpotPriceThreshold(0x4200000000000000000000000000000000000006, 200);
        values.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }
}
