// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { PxETHEthOracle } from "src/oracles/providers/PxETHEthOracle.sol";

contract AutopoolFeesAndThresholds is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        PxETHEthOracle oracle =
            new PxETHEthOracle(constants.sys.systemRegistry, constants.tokens.apxEth, constants.tokens.pxEth);

        console.log("PxETH Oracle: ", address(oracle));

        vm.stopBroadcast();
    }
}
