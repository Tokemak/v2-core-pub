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
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";

contract StatBridgingBaseReceipt is Script {
    Constants.Values public constants;

    uint64 public ccipBaseChainSelector = 15_971_525_489_660_198_786;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.MESSAGE_PROXY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);

        MessageProxy proxy = MessageProxy(payable(address(constants.sys.systemRegistry.messageProxy())));

        MessageProxy.MessageRouteConfig[] memory msgConfigs = new MessageProxy.MessageRouteConfig[](1);
        address eEthCalculator = address(
            constants.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                Stats.generateRawTokenIdentifier(constants.tokens.eEth)
            )
        );

        msgConfigs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: ccipBaseChainSelector, gas: 280_000 });
        proxy.addMessageRoutes(eEthCalculator, MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE, msgConfigs);

        if (!LSTCalculatorBase(eEthCalculator).destinationMessageSend()) {
            LSTCalculatorBase(eEthCalculator).setDestinationMessageSend();
        }

        constants.sys.accessController.revokeRole(Roles.MESSAGE_PROXY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
