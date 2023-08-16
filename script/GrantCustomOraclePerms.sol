// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;
// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Roles } from "src/libs/Roles.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract DeployCustomOracle is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("GOERLI_PRIVATE_KEY"));

        // CustomSetOracle o = CustomSetOracle(0x6804199d0C432d4be1b105D0cD0B02AE0AFE9EA5);
        // console.log(address(o));

        AccessController a = AccessController(0xAf647ee0FF2F8696CcaE6414aa42b0299B243231);
        a.grantRole(Roles.ORACLE_MANAGER_ROLE, 0xec19A67D0332f3b188740A2ea96F84CA3a17D73a);

        vm.stopBroadcast();
    }
}
