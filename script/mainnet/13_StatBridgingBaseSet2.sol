// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";

import { MessageProxy } from "src/messageProxy/MessageProxy.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";

contract StatBridgingBaseSet2 is Script {
    Constants.Values public constants;

    uint64 public ccipBaseChainSelector = 15_971_525_489_660_198_786;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);

        MessageProxy proxy = MessageProxy(payable(0x52bF30EA5870c66Ab2b5aF3E2E9A50E750596eb5));

        MessageProxy.MessageRouteConfig[] memory msgConfigs = new MessageProxy.MessageRouteConfig[](1);
        msgConfigs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: ccipBaseChainSelector, gas: 280_000 });
        proxy.addMessageRoutes(
            address(
                constants.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(constants.tokens.stEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            msgConfigs
        );

        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
