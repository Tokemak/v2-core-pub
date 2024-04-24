// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @title Send messages to our systems on other chains
interface IMessageProxy {
    /// @notice Data structure going across the wire to L2.  Encoded and stored in `data` field of EVM2AnyMessage
    /// Chainlink struct.
    struct Message {
        address l1Sender;
        uint256 version;
        uint256 messageTimestamp;
        bytes32 messageType;
        bytes message;
    }

    function sendMessage(bytes32 messageType, bytes memory message) external;
}
