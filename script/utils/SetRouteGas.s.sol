// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Stats } from "src/stats/Stats.sol";
import { Roles } from "src/libs/Roles.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";

contract ResendReceivingRouter is Script {
    uint64 public ccipBaseChainSelector = 15_971_525_489_660_198_786;

    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values.sys.accessController.grantRole(Roles.MESSAGE_PROXY_MANAGER, owner);

        values.sys.messageProxy.setGasForRoute(
            address(
                values.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(values.tokens.rEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipBaseChainSelector,
            280_000
        );
        values.sys.messageProxy.setGasForRoute(
            address(
                values.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(values.tokens.cbEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipBaseChainSelector,
            280_000
        );
        values.sys.messageProxy.setGasForRoute(
            address(
                values.sys.systemRegistry.statsCalculatorRegistry().getCalculator(
                    Stats.generateRawTokenIdentifier(values.tokens.stEth)
                )
            ),
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipBaseChainSelector,
            280_000
        );

        values.sys.accessController.revokeRole(Roles.MESSAGE_PROXY_MANAGER, owner);

        vm.stopBroadcast();
    }
}
