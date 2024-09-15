// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";

contract Router is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        AutopilotRouter router = new AutopilotRouter(constants.sys.systemRegistry);
        console.log("Autopilot Router: ", address(router));

        constants.sys.systemRegistry.setAutopilotRouter(address(router));

        vm.stopBroadcast();
    }
}
