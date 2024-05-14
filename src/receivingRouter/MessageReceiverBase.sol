// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IMessageReceiverBase } from "src/interfaces/receivingRouter/IMessageReceiverBase.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";

/// @title Inherited by message receiver contracts for cross chain interactions.
abstract contract MessageReceiverBase is SystemComponent, IMessageReceiverBase {
    /// @notice Thrown when message sender is not receiving router
    error NotReceivingRouter();

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    modifier onlyReceivingRouter() {
        if (msg.sender != address(systemRegistry.receivingRouter())) revert NotReceivingRouter();
        _;
    }

    /// @notice Called by ReceivingRouter.sol on message from ccipRouter that targets inheriting contract.
    /// @param message Encoded message from origin contract and chain.
    function onMessageReceive(bytes memory message) external override onlyReceivingRouter {
        _onMessageReceive(message);
    }

    /// @dev This function will decode the incoming message and perform any other actions needed.
    // slither-disable-next-line unimplemented-functions
    function _onMessageReceive(bytes memory message) internal virtual;
}
