// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";

import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract DeployOsethCalculator is BaseScript {
    bytes32 internal osEthTemplateId = keccak256("oseth");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);
        vm.startBroadcast(privateKey);

        RedstoneOracle oracle = new RedstoneOracle(systemRegistry);

        console.log(string.concat("Redstone Oracle Address: "), address(oracle));

        vm.stopBroadcast();
    }
}
