// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";

import { MessageProxy } from "src/messageProxy/MessageProxy.sol";
import { EthPerTokenSender } from "src/stats/calculators/bridged/EthPerTokenSender.sol";

contract StatBridging is Script {
    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        MessageProxy messageProxy = new MessageProxy(constants.sys.systemRegistry, constants.ext.ccipRouter);
        constants.sys.systemRegistry.setMessageProxy(address(messageProxy));
        console.log("MessageProxy: ", address(messageProxy));

        EthPerTokenSender ethPerTokenSender = new EthPerTokenSender(constants.sys.systemRegistry);
        console.log("EthPerTokenSender: ", address(ethPerTokenSender));

        bytes32[] memory calcs = new bytes32[](3);
        calcs[0] = Stats.generateRawTokenIdentifier(constants.tokens.rEth);
        calcs[1] = Stats.generateRawTokenIdentifier(constants.tokens.cbEth);
        calcs[2] = Stats.generateRawTokenIdentifier(constants.tokens.stEth);

        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);
        ethPerTokenSender.registerCalculators(calcs);
        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
