// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";
import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { LMPVault } from "src/vault/LMPVault.sol";

contract AddDestinations is BaseScript {
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        console.log("Owner: ", owner);

        AccessController access = AccessController(constants.sys.accessController);
        access.grantRole(Roles.DESTINATION_VAULTS_UPDATER, owner);

        LMPVault est = LMPVault(0x48baD772E94669B8e1b3F2258EEdC8bfF5f100e1);
        LMPVault emg = LMPVault(0x76969Dd3e1102D4c5e43039F121dD22D1d599Cfd);

        address[] memory estDest = new address[](2);
        estDest[0] = 0x49466C2D0842f64de3b18e2A198186E6a2415f93;
        estDest[1] = 0x9F2106aF7d783bB5341631d8D700696760F95943;

        address[] memory emgDest = new address[](1);
        emgDest[0] = 0x9F2106aF7d783bB5341631d8D700696760F95943;

        est.addDestinations(estDest);
        emg.addDestinations(emgDest);

        vm.stopBroadcast();
    }
}
