// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;
// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract DeployCustomOracle is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("GOERLI_PRIVATE_KEY"));

        CustomSetOracle o = new CustomSetOracle(ISystemRegistry(0x849f823FdC00ADF8AAD280DEA89fe2F7a0be48a3), 86400);
        console.log(address(o));

        vm.stopBroadcast();
    }
}
