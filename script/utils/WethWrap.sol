// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

contract WethWrap is Script {
    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN1_SEPOLIA);

        vm.startBroadcast();

        values.sys.systemRegistry.weth().deposit{ value: 0.3e18 }();

        vm.stopBroadcast();
    }
}
