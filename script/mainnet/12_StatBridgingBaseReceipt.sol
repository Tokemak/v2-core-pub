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

contract StatBridgingBaseReceipt is Script {
    Constants.Values public constants;

    uint64 public ccipBaseChainSelector = 15_971_525_489_660_198_786;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.MESSAGE_PROXY_MANAGER, owner);

        MessageProxy proxy = MessageProxy(payable(address(constants.sys.systemRegistry.messageProxy())));

        proxy.setDestinationChainReceiver(
            ccipBaseChainSelector,
            0xDaDE384d5C82e9D38159403EA4E212c4204ae9Df // Base Receiving Router
        );

        MessageProxy.MessageRouteConfig[] memory msgConfigs = new MessageProxy.MessageRouteConfig[](1);
        msgConfigs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: ccipBaseChainSelector, gas: 280_000 });
        proxy.addMessageRoutes(
            address(
                constants.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(constants.tokens.rEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            msgConfigs
        );

        proxy.addMessageRoutes(
            address(
                constants.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(constants.tokens.cbEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            msgConfigs
        );

        // Eth Per Token Store
        proxy.addMessageRoutes(
            0x4a6dc8aFB1167e6e55c022fbC3f38bCd5dCec66c, MessageTypes.LST_BACKING_MESSAGE_TYPE, msgConfigs
        );

        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
