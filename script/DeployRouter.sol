// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "./BaseScript.sol";
import { Systems } from "./utils/Constants.sol";

import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";

contract DeployLens is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(privateKey);

        LMPVaultRouter o = new LMPVaultRouter(systemRegistry, constants.tokens.weth);
        console.log("Router Address: %s", address(o));

        systemRegistry.setLMPVaultRouter(address(o));

        vm.stopBroadcast();
    }
}
