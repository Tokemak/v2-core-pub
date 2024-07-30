// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { console } from "forge-std/console.sol";

import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";

contract RedeployRouter is Script {
    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN1_SEPOLIA);

        vm.startBroadcast();

        AutopilotRouter router = new AutopilotRouter(values.sys.systemRegistry);

        values.sys.systemRegistry.setAutopilotRouter(address(router));

        console.log("Router: ", address(router));

        vm.stopBroadcast();
    }
}
