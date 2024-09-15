// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { console } from "forge-std/console.sol";

import { Lens } from "src/lens/Lens.sol";

contract RedeployLens is Script {
    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        Lens lens = new Lens(values.sys.systemRegistry);

        console.log("Lens: ", address(lens));

        vm.stopBroadcast();
    }
}
