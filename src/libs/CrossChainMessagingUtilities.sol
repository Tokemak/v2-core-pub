// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";

/// @title Contains some common errors, events, structs, functionality for cross chain comms.
library CrossChainMessagingUtilities {
    /// =====================================================
    /// Constants
    /// =====================================================

    uint256 public constant VERSION = 1;

    /// =====================================================
    /// Errors
    /// =====================================================

    error ChainNotSupported(uint64 chainId);

    error MismatchMessageHash(bytes32 storedHash, bytes32 currentHash);

    error VersionMismatch(uint256 messageProxyVersion, uint256 receivingRouterVersion);

    /// =====================================================
    /// Structs
    /// =====================================================

    struct Message {
        address messageOrigin;
        uint256 version;
        uint256 messageTimestamp;
        bytes32 messageType;
        bytes message;
    }

    /// =====================================================
    /// External Functions
    /// =====================================================

    /// @notice Returns current version of Message struct.
    function getVersion() external pure returns (uint256) {
        return VERSION;
    }

    /// @notice Encodes message to be sent to receiving chain
    /// @param sender Message sender
    /// @param messageTimestamp Timestamp of message to be sent
    /// @param messageType message type to be sent
    /// @param message Bytes message to be processed on receiving chain
    function encodeMessage(
        address sender,
        uint256 messageTimestamp,
        bytes32 messageType,
        bytes memory message
    ) external pure returns (bytes memory) {
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

    /// @notice Validates the chain selector with the ccip router
    function _validateChain(IRouterClient routerClient, uint64 chain) public view {
        if (!routerClient.isChainSupported(chain)) {
            revert ChainNotSupported(chain);
        }
    }
}
