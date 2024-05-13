// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IMessageReceiverBase } from "src/interfaces/receivingRouter/IMessageReceiverBase.sol";
import { Errors } from "src/utils/Errors.sol";

abstract contract MessageReceiverBase is IMessageReceiverBase {
    // If no setter this should be immutable
    address public receivingRouter;

    error NotReceivingRouter();

    constructor(address _receivingRouter) {
        Errors.verifyNotZero(_receivingRouter, "_receivingRouter");
    }

    modifier onlyReceivingRouter() {
        if (msg.sender != receivingRouter) revert NotReceivingRouter();
        _;
    }

    function onMessageReceive(bytes memory message) external override onlyReceivingRouter {
        _onMessageReceive(message);
    }

    function _onMessageReceive(bytes memory message) internal virtual;
}
