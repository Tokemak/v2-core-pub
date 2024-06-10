// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count,no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { ReceivingRouter } from "src/receivingRouter/ReceivingRouter.sol";

contract ResendReceivingRouter is Script {
    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values.sys.accessController.grantRole(Roles.RECEIVING_ROUTER_EXECUTOR, owner);
        ReceivingRouter router = ReceivingRouter(0xDaDE384d5C82e9D38159403EA4E212c4204ae9Df);
        address[] memory receivers = new address[](1);
        receivers[0] = 0x29941E00d6b321CfaAB892947eE0284e83F6b68A;
        ReceivingRouter.ResendArgsReceivingChain[] memory msgs = new ReceivingRouter.ResendArgsReceivingChain[](1);
        msgs[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: 0x059C6005b96ED7a71dD34BFF700800Ddd61A1A38,
            messageType: hex"3E9C7A8767D3790A3E992D4112A3613FD19E69407CE8607DBC7053A0A18A90DE",
            messageResendTimestamp: 1_717_884_539,
            sourceChainSelector: 5_009_297_550_715_157_269,
            message: hex"000000000000000000000000000000000000000000000000000000006664D67B0000000000000000000000000000000000000000000000000065D5F71B1B89DC0000000000000000000000000000000000000000000000000EE57D0929481A32",
            messageReceivers: receivers
        });
        router.resendLastMessage(msgs);

        values.sys.accessController.revokeRole(Roles.RECEIVING_ROUTER_EXECUTOR, owner);

        vm.stopBroadcast();
    }
}
