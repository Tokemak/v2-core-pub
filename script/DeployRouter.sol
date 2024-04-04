// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Systems } from "./utils/Constants.sol";
import { BaseScript, console } from "./BaseScript.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";

contract DeployLens is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(privateKey);

        LMPVaultRouter o = new LMPVaultRouter(systemRegistry);
        console.log("Router Address: %s", address(o));

        systemRegistry.setLMPVaultRouter(address(o));

        vm.stopBroadcast();
    }
}
