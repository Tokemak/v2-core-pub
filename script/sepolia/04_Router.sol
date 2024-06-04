// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";

contract PoolAndStrategy is Script {
    bytes32 public autopoolType = keccak256("lst-weth-v1");

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_SEPOLIA);

        vm.startBroadcast();

        AutopilotRouter router = new AutopilotRouter(constants.sys.systemRegistry);
        console.log("AutopoolRouter: ", address(router));

        constants.sys.systemRegistry.setAutopilotRouter(address(router));

        vm.stopBroadcast();
    }
}
