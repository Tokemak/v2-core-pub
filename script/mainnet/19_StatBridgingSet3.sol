// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

contract StatBridgingSet3 is Script {
    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        bytes32[] memory calcs = new bytes32[](1);
        calcs[0] = keccak256(abi.encode("lst", constants.tokens.weEth));

        // This will send the value to the destination chain immediately
        // Ensure the store on the destination is setup to receive it

        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);
        constants.sys.ethPerTokenSender.registerCalculators(calcs);
        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
