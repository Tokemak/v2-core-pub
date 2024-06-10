// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { ChainlinkEthPerTokenSenderUpkeep } from "src/stats/calculators/bridged/ChainlinkEthPerTokenSenderUpkeep.sol";

contract ChainlinkPerTokenSender is Script {
    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        ChainlinkEthPerTokenSenderUpkeep s = new ChainlinkEthPerTokenSenderUpkeep();
        console.log("ChainlinkEthPerTokenSenderUpkeep:", address(s));

        vm.stopBroadcast();
    }
}
