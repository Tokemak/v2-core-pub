// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { IRouter } from "src/interfaces/external/chainlink/IRouter.sol";
//import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";
//import { Client } from "src/external/chainlink/ccip/Client.sol";

/// @title Send messages to our systems on other chains
contract MessageProxy is IMessageProxy {
    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    IRouter public immutable router;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Receiver contracts on the destination chains
    /// @dev mapping is destinationChainSelector -> our receiver contract
    mapping(uint64 => address) public destinationChainReceivers;

    /// @notice Receiver contracts on the destination chains
    /// @dev mapping is msg.sender -> messageType -> messageHash.
    mapping(address => mapping(bytes32 => bytes32)) public lastMessageSent;

    /// @notice Count of messages received from our internal system
    /// @dev 0 is none. 1st message we get will be 1
    uint256 public lastMessageIx;

    /// =====================================================
    /// Private Vars
    /// =====================================================

    /// @notice Routes configured for a message and sender
    /// @dev mapping is msg.sender -> messageType -> routes. Exposed via getMessageRoutes()
    mapping(address => mapping(bytes32 => MessageRouteConfig[])) private _messageRoutes;

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @notice Data structure going across the wire to L2
    struct Message {
        address l1Sender;
        uint256 version;
        uint256 messageIx;
        bytes32 messageType;
        bytes message;
    }

    /// @notice Destination chain to send a message to and the gas required for that chain
    struct MessageRouteConfig {
        uint64 destinationChainSelector;
        uint256 gas;
    }

    /// @notice Arguments used to resend the last message for a sender + type
    struct RetryArgs {
        address msgSender;
        bytes32 messageType;
        bytes message;
        uint64[] destinationChainSelector;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(IRouter ccipRouter) {
        Errors.verifyNotZero(address(ccipRouter), "router");

        router = ccipRouter;
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function sendMessage(bytes32 messageType, bytes memory message) external override {
        // Lookup message routes from _messageRoutes

        // If there are zero routes, then just return, nothing to do
        // Routes act as our security

        // If there are routes:

        //      Get our messageIx = ++lastMessageIx;
        //      Build and hash our Message struct and hash it ->
        //          keccak256(abi.encode(messageIx, sender, messageType, message)), hash is for our internal tracking
        //      Store hash in lastMessageSent for sender+type
        //      Emit event Message(message hash (indexed), messageIx, msg.sender, messageType, message (bytes))
        //      Take our Message struct, encode to string, string(abi.encode())

        //      For each destination:
        //          Look up our receiver contract on the destination chain destinationChainReceivers
        //          Build the Client.EVM2AnyMessage with the string, receiver contract, and gas
        //
        //          Get fees, router.getFee()
        //          bytes32 messageId = 0
        //          if we don't have enough fees to cover:
        //              emit event NotEnoughFees(destChainId, message hash)
        //              continue;

        //          if we have enough eth to cover the fee:
        //              try catch Send message router.ccipSend() returns (ccipMsgId)
        //                  emit MessageSent(destChainId, message hash, ccipMsgId)
        //              catch
        //                  emit MessageFailure(destChainId, message hash)
    }

    /// @notice Resend the last message sent for a sender + type
    /// @dev Caller must send in ETH to cover router fees. Cannot use contract balance
    function resendLastMessage(RetryArgs[] memory args) external payable {
        // uint256 ethSent = msg.value; // Snapshot eth sent
        // for each message:
        //      Same hashing as main send, same "Emit event Message"
        //
    }

    /// @notice Estimate fees off-chain for purpose of retries
    function getFee(
        address messageSender,
        bytes32 messageType,
        bytes memory message
    ) external view returns (uint64[] memory chainId, uint256[] memory gas) {
        // Lookup destinations for the sender and type
        // Build Client.EVM2AnyMessage for them
        // Get and return router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    function getMessageRoutes(
        address sender,
        bytes32 messageType
    ) external view returns (MessageRouteConfig[] memory routes) {
        uint256 len = _messageRoutes[sender][messageType].length;
        routes = new MessageRouteConfig[](len);
        for (uint256 i = 0; i < len; ++i) {
            routes[i] = _messageRoutes[sender][messageType][i];
        }
    }
}
