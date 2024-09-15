// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { ChainlinkStatsUpkeepV4 } from "src/stats/ChainlinkStatsUpkeepV4.sol";

contract CalcKeeperDeploy is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        ChainlinkStatsUpkeepV4 upKeep = new ChainlinkStatsUpkeepV4();
        console.log("Chainlink Calculator Upkeep: ", address(upKeep));

        console.log("Check data");
        console.logBytes(abi.encode(address(constants.sys.systemRegistry)));

        constants.sys.accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(upKeep));

        vm.stopBroadcast();
    }
}
