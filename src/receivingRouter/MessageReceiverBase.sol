// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IMessageReceiverBase } from "src/interfaces/receivingRouter/IMessageReceiverBase.sol";
import { Errors } from "src/utils/Errors.sol";

/// @title Inherited by message receiver contracts for cross chain interactions.
abstract contract MessageReceiverBase is IMessageReceiverBase {
    // TODO: This will be moved to SystemRegistry.
    address public receivingRouter;

    /// @notice Thrown when message sender is not receiving router
    error NotReceivingRouter();

    // TODO: Will take in systemregistry, become systemcomponent etc
    constructor(address _receivingRouter) {
        Errors.verifyNotZero(_receivingRouter, "_receivingRouter");
    }

    // TODO: This wil call system registry.
    modifier onlyReceivingRouter() {
        if (msg.sender != receivingRouter) revert NotReceivingRouter();
        _;
    }

    /// @notice Called by ReceivingRouter.sol on message from ccipRouter that targets inheriting contract.
    /// @param message Encoded message from origin contract and chain.
    function onMessageReceive(bytes memory message) external override onlyReceivingRouter {
        _onMessageReceive(message);
    }

    /// @dev This function will decode the incoming message and perform any other actions needed.
    function _onMessageReceive(bytes memory message) internal virtual;
}
