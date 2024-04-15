// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Lens } from "src/lens/Lens.sol";
import { Systems } from "./utils/Constants.sol";
import { BaseScript, console } from "./BaseScript.sol";

contract DeployLens is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);
        vm.startBroadcast(privateKey);

        Lens o = new Lens(systemRegistry);
        console.log("Lens Address: %s", address(o));

        vm.stopBroadcast();
    }
}
