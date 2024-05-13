// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";

/// @title Contains some common errors, events, structs, functionality for cross chain comms.

/**
 * NOTES
 *
 * Events, errors, _validateChain, common imports, maybe some hashing, decoding, encoding can all go here.
 *
 * QUESTIONS
 */
library CrossChainMessagingUtilities {
    uint256 public constant VERSION = 1;

    error ChainNotSupported(uint64 chainId);

    event MessageData(
        bytes32 indexed messageHash, uint256 messageTimestamp, address sender, bytes32 messageType, bytes message
    );

    // Not sure if this should be here or in separate interface.
    struct Message {
        address messageOrigin;
        uint256 version;
        uint256 messageTimestamp;
        bytes32 messageType;
        bytes message;
    }

    /// @notice Encodes message to be sent to receiving chain
    /// @param sender Message sender
    /// @param messageTimestamp Timestamp of message to be sent
    /// @param messageType message type to be sent
    /// @param message Bytes message to be processed on receiving chain.
    function encodeMessage(
        address sender,
        uint256 messageTimestamp,
        bytes32 messageType,
        bytes memory message
    ) public pure returns (bytes memory) {
        return abi.encode(
            Message({
                messageOrigin: sender,
                version: VERSION,
                messageTimestamp: messageTimestamp,
                messageType: messageType,
                message: message
            })
        );
    }

    function _validateChain(IRouterClient routerClient, uint64 chain) public view {
        if (!routerClient.isChainSupported(chain)) {
            revert ChainNotSupported(chain);
        }
    }
}
