// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IMessageReceiverBase } from "src/interfaces/receivingRouter/IMessageReceiverBase.sol";

import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { CrossChainMessagingUtilities as CCUtils, IRouterClient } from "src/libs/CrossChainMessagingUtilities.sol";

import { CCIPReceiver } from "src/external/chainlink/ccip/CCIPReceiver.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";

contract ReceivingRouter is CCIPReceiver, SystemComponent, SecurityBase {
    struct ResendArgsReceivingChain {
        address messageOrigin;
        bytes32 messageType;
        uint256 messageRetryTimestamp;
        bytes message;
        address[] receivers;
    }

    /// @notice address sender => bytes32 messageType => address[]
    mapping(address => mapping(bytes32 => address[])) public messageReceivers;

    /// @notice uint256 sourceChainId => address sender
    /// @dev The contract that sends the message across chains
    mapping(uint256 => address) public sourceChainSenders;

    /// @notice address sender => bytes32 messageType => bytes32 hash
    mapping(address => mapping(bytes32 => bytes32)) public lastMessageSent;

    /// =====================================================
    /// Errors
    /// =====================================================

    /// @notice Thrown when message data is different on retry, resulting in mismatch hash.
    error MismatchMessageHash(bytes32 storedHash, bytes32 currentHash);

    /// =====================================================
    /// Failure Events
    /// =====================================================

    event InvalidSenderFromSource(uint256 sourceChainSelector, address sourceChainSender);

    event NoMessageReceiversRegistered(address origin, bytes32 messageType);

    /// =====================================================
    /// Events
    /// =====================================================

    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);

    event SourceChainSenderDeleted(uint64 sourceChainSelector);

    event MessageReceived(address receiver, address origin, bytes32 messageType, bytes32 messageHash);

    event MessageFailed(address receiver, address origin, bytes32 messageType, bytes32 messageHash);

    event MessageReceiverDeleted(address origin, bytes32 messageType, address receiverToRemove);

    constructor(
        address _ccipRouter,
        ISystemRegistry _systemRegistry
    )
        CCIPReceiver(_ccipRouter)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// @inheritdoc CCIPReceiver
    function _ccipReceive(Client.Any2EVMMessage memory ccipMessage) internal override {
        uint256 sourceSelector = ccipMessage.sourceChainSelector;
        address sender = abi.decode(ccipMessage.sender, (address));
        bytes memory messageData = ccipMessage.data;

        if (sourceChainSenders[sourceSelector] != sender) {
            emit InvalidSenderFromSource(sourceSelector, sender);
            return;
        }

        CCUtils.Message memory messageFromProxy = decodeMessage(messageData);

        address origin = messageFromProxy.messageOrigin;
        bytes32 messageType = messageFromProxy.messageType;
        bytes memory message = messageFromProxy.message;

        // Think this can be removed
        if (message.length == 0) {
            return;
            // emit MessageLengthZero
        }

        address[] memory receiversForRoute = messageReceivers[origin][messageType];
        uint256 receiversForRouteLength = receiversForRoute.length;

        // This may be able to revert.
        if (receiversForRouteLength == 0) {
            emit NoMessageReceiversRegistered(origin, messageType);
            return;
        }

        // Hash encoded Message struct.
        bytes32 messageHash = keccak256(messageData);
        lastMessageSent[origin][messageType] = messageHash;

        emit CCUtils.MessageData(messageHash, messageFromProxy.messageTimestamp, origin, messageType, message);

        for (uint256 i = 0; i < receiversForRouteLength; ++i) {
            address currentReceiver = receiversForRoute[i];
            try IMessageReceiverBase(currentReceiver).onMessageReceive(message) {
                emit MessageReceived(currentReceiver, origin, messageType, messageHash);
            } catch {
                emit MessageFailed(currentReceiver, origin, messageType, messageHash);
            }
        }
    }

    function resendLastMessage(ResendArgsReceivingChain[] memory args)
        external
        hasRole(Roles.RECEIVING_ROUTER_MANAGER)
    {
        // Loop through ResendArgsReceivingChain array.
        for (uint256 i = 0; i < args.length; ++i) {
            // Store vars with multiple usages locally
            ResendArgsReceivingChain memory currentResend = args[i];
            address messageOrigin = currentResend.messageOrigin;
            bytes32 messageType = currentResend.messageType;
            bytes memory message = currentResend.message;
            address[] memory receivers = currentResend.receivers;

            // Get hash from data passed in, hash from last message, revert if they are not equal.
            bytes32 currentMessageHash = keccak256(
                CCUtils.encodeMessage(messageOrigin, currentResend.messageRetryTimestamp, messageType, message)
            );

            {
                bytes32 storedMessageHash = lastMessageSent[messageOrigin][messageType];
                if (currentMessageHash != storedMessageHash) {
                    revert MismatchMessageHash(storedMessageHash, currentMessageHash);
                }
            }

            // Loop through and send messages.
            for (uint256 j = 0; j < receivers.length; ++j) {
                address currentReceiver = receivers[j];

                Errors.verifyNotZero(currentReceiver, "currentReceiver");

                emit MessageReceived(currentReceiver, messageOrigin, messageType, currentMessageHash);
                IMessageReceiverBase(currentReceiver).onMessageReceive(message);
            }
        }
    }

    function setMessageReceivers(
        address origin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory receivers
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Needs to be able to set nultiple destinations for each messageType,origin,source functionality
        // Needs check to make sure this is a destination or something along those lines
        Errors.verifyNotZero(origin, "origin");
        Errors.verifyNotZero(messageType, "messageType");

        uint256 receiversLength = receivers.length;
        Errors.verifyNotZero(receiversLength, "destinationsLength");

        // Handles valid chain selector and chain being set.
        if (sourceChainSenders[sourceChainSelector] == address(0)) {
            revert CCUtils.ChainNotSupported(sourceChainSelector);
        }

        address[] memory currentStoredReceivers = messageReceivers[origin][messageType];
        uint256 currentStoredReceiversLength = currentStoredReceivers.length;
        for (uint256 i = 0; i < receiversLength; ++i) {
            address receiverToAdd = receivers[i];
            Errors.verifyNotZero(receiverToAdd, "receiverToAdd");

            if (currentStoredReceiversLength > 0) {
                for (uint256 j = 0; j < currentStoredReceiversLength; ++j) {
                    if (receiverToAdd == currentStoredReceivers[j]) {
                        revert Errors.ItemExists();
                    }
                }
            }

            messageReceivers[origin][messageType].push(receiverToAdd);
        }
    }

    function removeMessageReceivers(
        address origin,
        bytes32 messageType,
        address[] memory receivers
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        uint256 receiversLength = receivers.length;
        Errors.verifyNotZero(receiversLength, "destinationsLength");

        address[] storage receiversStored = messageReceivers[origin][messageType];

        for (uint256 i = 0; i < receiversLength; ++i) {
            uint256 receiversStoredLength = receiversStored.length;
            address receiverToRemove = receivers[i];
            if (receiversStoredLength == 0) {
                revert Errors.ItemNotFound();
            }
            // For each route we want to remove, loop through stored routes.
            uint256 j = 0;
            for (; j < receiversStoredLength; ++j) {
                // If route to add is equal to a stored route, remove.
                if (receiverToRemove == receiversStored[j]) {
                    emit MessageReceiverDeleted(origin, messageType, receiverToRemove);

                    // For each route, record index of storage array that was deleted.
                    receiversStored[j] = receiversStored[receiversStored.length - 1];
                    receiversStored.pop();

                    // Can only have one message route per dest chain selector, when we find it break for loop.
                    break;
                }
            }

            // If we get to the end of the currentStoredRoutes array, item to be deleted does not exist.
            if (j == receiversStoredLength) {
                revert Errors.ItemNotFound();
            }
        }
    }

    /// @notice Sets valid sender for source chain.
    /// @dev This will be the message proxy contract on the source chain.
    function setSourceChainSenders(
        uint64 sourceChainSelector,
        address sourceChainSender
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        Errors.verifyNotZero(sourceChainSender, "sourceChainSender");
        CCUtils._validateChain(IRouterClient(i_ccipRouter), sourceChainSelector);

        if (sourceChainSenders[sourceChainSelector] != address(0)) {
            revert Errors.ItemExists();
        }

        emit SourceChainSenderSet(sourceChainSelector, sourceChainSender);
        sourceChainSenders[sourceChainSelector] = sourceChainSender;
    }

    /// @notice Removes sender for source chain selector.
    function removeSourceChainSenders(uint64 sourceChainSelector) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        if (sourceChainSenders[sourceChainSelector] == address(0)) {
            revert Errors.ItemNotFound();
        }

        emit SourceChainSenderDeleted(sourceChainSelector);
        delete sourceChainSenders[sourceChainSelector];
    }

    function decodeMessage(bytes memory encodedMessage) internal pure returns (CCUtils.Message memory) {
        return abi.decode(encodedMessage, (CCUtils.Message));
    }
}
