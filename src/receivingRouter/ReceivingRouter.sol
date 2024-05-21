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
import { Client } from "src/external/chainlink/ccip/Client.sol";

import { CCIPReceiver } from "src/external/chainlink/ccip/CCIPReceiver.sol";

/// @title Receives and routes messages from another chain using Chainlink CCIP
contract ReceivingRouter is CCIPReceiver, SystemComponent, SecurityBase {
    /// =====================================================
    /// Public vars
    /// =====================================================

    /// @notice keccak256(address origin, uint256 sourceChainSelector, bytes32 messageType) => address[]
    mapping(bytes32 => address[]) public messageReceivers;

    /// @notice uint64 sourceChainSelector => address sender, contract that sends message across chain (MessageProxy)
    mapping(uint64 => address) public sourceChainSenders;

    /// @notice keccak256(address origin, uint256 sourceChainSelector, bytes32 messageType) => bytes32 hash
    mapping(bytes32 => bytes32) public lastMessageReceived;

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @notice Used for resending messages that fail on _ccipReceive
    struct ResendArgsReceivingChain {
        address messageOrigin; // Origin of message on source chain. Different from sender
        bytes32 messageType;
        uint256 messageResendTimestamp;
        uint64 sourceChainSelector;
        bytes message;
        address[] messageReceivers;
    }

    /// =====================================================
    /// Errors
    /// =====================================================

    /// @notice Thrown when a message receiver does not exist in storage.
    error MessageReceiverDoesNotExist(address notReceiver);

    /// =====================================================
    /// Events
    /// =====================================================

    /// @notice Emitted when message is built to be sent for message origin, type, and source chain.
    event MessageData(
        bytes32 indexed messageHash,
        uint256 messageTimestamp,
        address messageOrigin,
        bytes32 messageType,
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        bytes message
    );

    /// @notice Emitted when the contract that sends messages from the source chain is registered.
    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);

    /// @notice Emitted when source contract is deleted.
    event SourceChainSenderDeleted(uint64 sourceChainSelector);

    /// @notice Emitted when a message is successfully sent to a message receiver contract.
    event MessageReceived(address messageReceiver, bytes32 messageHash);

    /// @notice Emitted when a message is successfully sent to a message receiver contract on a resend.
    event MessageReceivedOnResend(address currentReceiver, bytes32 messageHash);

    /// @notice Emitted when a message receiver is added
    event MessageReceiverAdded(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToAdd
    );

    /// @notice Emitted when a message receiver is deleted
    event MessageReceiverDeleted(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToRemove
    );

    /// =====================================================
    /// Failure Events
    /// =====================================================

    /// @notice Emitted when an invalid address sends a message from the source chain
    event InvalidSenderFromSource(
        uint256 sourceChainSelector, address sourceChainSender, address sourceChainSenderRegistered
    );

    /// @notice Emitted when no message receivers are registered
    event NoMessageReceiversRegistered(address messageOrigin, bytes32 messageType, uint64 sourceChainSelector);

    /// @notice Emitted when message versions don't match
    event MessageVersionMismatch(uint256 versionSource, uint256 versionReceiver);

    /// @notice Emitted when message send to a receiver fails
    event MessageFailed(address messageReceiver, bytes32 messageHash);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        address _ccipRouter,
        ISystemRegistry _systemRegistry
    )
        CCIPReceiver(_ccipRouter)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @inheritdoc CCIPReceiver
    /// @dev This function can fail if incorrect data comes in on the Any2EVMMessage.data field. Special care
    ///   should be taken care to make sure versions always match
    function _ccipReceive(Client.Any2EVMMessage memory ccipMessage) internal override {
        uint64 sourceChainSelector = ccipMessage.sourceChainSelector;
        bytes memory messageData = ccipMessage.data;

        // Scope stack too deep
        {
            // Checking that sender in Any2EVMMessage struct is the same as the one we have registered for source
            address proxySender = abi.decode(ccipMessage.sender, (address));
            address registeredSender = sourceChainSenders[sourceChainSelector];
            if (registeredSender != proxySender) {
                emit InvalidSenderFromSource(sourceChainSelector, proxySender, registeredSender);
                return;
            }
        }

        CCUtils.Message memory messageFromProxy = decodeMessage(messageData);

        // Scope stack too deep
        {
            // Checking Message struct versioning
            uint256 sourceVersion = messageFromProxy.version;
            uint256 receiverVersion = CCUtils.getVersion();
            if (sourceVersion != receiverVersion) {
                emit MessageVersionMismatch(sourceVersion, receiverVersion);
                return;
            }
        }

        address origin = messageFromProxy.messageOrigin;
        bytes32 messageType = messageFromProxy.messageType;
        bytes memory message = messageFromProxy.message;

        bytes32 receiverKey = _getMessageReceiversKey(origin, sourceChainSelector, messageType);
        address[] memory messageReceiversForRoute = messageReceivers[receiverKey];
        uint256 messageReceiversForRouteLength = messageReceiversForRoute.length;

        // Receivers registration act as security, this accounts for zero checks for type, origin, selector.
        if (messageReceiversForRouteLength == 0) {
            emit NoMessageReceiversRegistered(origin, messageType, sourceChainSelector);
            return;
        }

        // Set message hash for retries
        bytes32 messageHash = keccak256(messageData);
        lastMessageReceived[receiverKey] = messageHash;

        emit MessageData(
            messageHash,
            messageFromProxy.messageTimestamp,
            origin,
            messageType,
            ccipMessage.messageId,
            sourceChainSelector,
            message
        );

        // Loop through stored receivers, send messages off to them
        for (uint256 i = 0; i < messageReceiversForRouteLength; ++i) {
            address currentMessageReceiver = messageReceiversForRoute[i];
            // slither-disable-start reentrancy-events
            // Try to send message to receiver, catch any errors and emit event
            try IMessageReceiverBase(currentMessageReceiver).onMessageReceive(messageType, message) {
                emit MessageReceived(currentMessageReceiver, messageHash);
            } catch {
                emit MessageFailed(currentMessageReceiver, messageHash);
            }
            // slither-disable-end reentrancy-events
        }
    }

    /// @notice Used to resend messages that failed when attempting to go to message receivers
    /// @dev This can be used even if messages did not fail, be aware of receivers being sent in
    /// @param args Array of Resend structs with information for retries
    function resendLastMessage(ResendArgsReceivingChain[] memory args)
        external
        hasRole(Roles.RECEIVING_ROUTER_EXECUTOR)
    {
        // Loop through ResendArgsReceivingChain array.
        for (uint256 i = 0; i < args.length; ++i) {
            // Store vars with multiple usages locally
            ResendArgsReceivingChain memory currentResend = args[i];
            address messageOrigin = currentResend.messageOrigin;
            bytes32 messageType = currentResend.messageType;
            bytes memory message = currentResend.message;
            address[] memory resendMessageReceivers = currentResend.messageReceivers;
            uint256 resendMessageReceiversLength = resendMessageReceivers.length;

            // Verify that message receivers are sent in.
            Errors.verifyNotZero(resendMessageReceiversLength, "resendMessageReceiversLength");

            // Get hash from data passed in for comparison to stored hash
            bytes32 currentMessageHash = keccak256(
                CCUtils.encodeMessage(messageOrigin, currentResend.messageResendTimestamp, messageType, message)
            );
            bytes32 messageReceiverKey =
                _getMessageReceiversKey(messageOrigin, currentResend.sourceChainSelector, messageType);

            // Check message hashes.  Acts as security for origin, timestamp, type, selector, message passed in
            {
                bytes32 storedMessageHash = lastMessageReceived[messageReceiverKey];
                if (currentMessageHash != storedMessageHash) {
                    revert CCUtils.MismatchMessageHash(storedMessageHash, currentMessageHash);
                }
            }

            // Get receivers registered, check that there is at least one
            address[] memory storedMessageReceiversForKey = messageReceivers[messageReceiverKey];
            uint256 storedReceiversLength = storedMessageReceiversForKey.length;
            Errors.verifyNotZero(storedReceiversLength, "storedReceiversLength");

            // Loop through and send messages.
            for (uint256 j = 0; j < resendMessageReceiversLength; ++j) {
                address currentReceiver = resendMessageReceivers[j];
                Errors.verifyNotZero(currentReceiver, "currentReceiver");

                // Checking that message receiver exists in our registered receivers information.
                uint256 k;
                for (; k < storedReceiversLength; ++k) {
                    // Break for loop if we have a match
                    if (currentReceiver == storedMessageReceiversForKey[k]) {
                        break;
                    }
                }
                // Revert if for loop finishes without finding match, not registered
                if (k == storedReceiversLength) {
                    revert MessageReceiverDoesNotExist(currentReceiver);
                }

                // slither-disable-start reentrancy-events
                emit MessageReceivedOnResend(currentReceiver, currentMessageHash);
                IMessageReceiverBase(currentReceiver).onMessageReceive(messageType, message);
                // slither-disable-end reentrancy-events
            }
        }
    }

    /// @notice Sets message receivers for an origin, type, source selector combination
    /// @param messageOrigin Original sender of message on source chain.
    /// @param messageType Bytes32 message type
    /// @param sourceChainSelector Selector of the source chain
    /// @param messageReceiversToSet Array of receiver addresses to set
    function setMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToSet
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Verify no zeros
        Errors.verifyNotZero(messageOrigin, "messageOrigin");
        Errors.verifyNotZero(messageType, "messageType");

        // Store and verify length of array
        uint256 messageReceiversToSetLength = messageReceiversToSet.length;
        Errors.verifyNotZero(messageReceiversToSetLength, "messageReceiversToSetLength");

        // Check to make sure that chain is valid and has a sender set
        if (sourceChainSenders[sourceChainSelector] == address(0)) {
            revert CCUtils.ChainNotSupported(sourceChainSelector);
        }

        bytes32 receiverKey = _getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType);

        // Loop and add to storage array
        for (uint256 i = 0; i < messageReceiversToSetLength; ++i) {
            address receiverToAdd = messageReceiversToSet[i];
            Errors.verifyNotZero(receiverToAdd, "receiverToAdd");

            address[] memory currentStoredMessageReceivers = messageReceivers[receiverKey];
            uint256 currentStoredMessageReceiversLength = currentStoredMessageReceivers.length;

            // Check for duplicates being added
            if (currentStoredMessageReceiversLength > 0) {
                for (uint256 j = 0; j < currentStoredMessageReceiversLength; ++j) {
                    if (receiverToAdd == currentStoredMessageReceivers[j]) {
                        revert Errors.ItemExists();
                    }
                }
            }

            emit MessageReceiverAdded(messageOrigin, sourceChainSelector, messageType, receiverToAdd);
            messageReceivers[receiverKey].push(receiverToAdd);
        }
    }

    /// @notice Removes registered message receivers
    /// @param messageOrigin Origin of message
    /// @param messageType Type of message
    /// @param sourceChainSelector Selector of the source chain
    /// @param messageReceiversToRemove Array of sender addresses to remove
    function removeMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToRemove
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Check array length
        uint256 messageReceiversToRemoveLength = messageReceiversToRemove.length;
        Errors.verifyNotZero(messageReceiversToRemoveLength, "messageReceiversToRemoveLength");

        // Get stored receivers as storage, manipulating later.
        // Acts as security for origin, type, selector.  If none registered, will revert.  Zeros checked on reg
        address[] storage messageReceiversStored =
            messageReceivers[_getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType)];

        // Loop through removal array
        for (uint256 i = 0; i < messageReceiversToRemoveLength; ++i) {
            // Check for storage length.  Do this in loop because we are updating as we go
            uint256 receiversStoredLength = messageReceiversStored.length;
            if (receiversStoredLength == 0) {
                revert Errors.ItemNotFound();
            }

            address receiverToRemove = messageReceiversToRemove[i];
            Errors.verifyNotZero(receiverToRemove, "receiverToRemove");

            // For each route we want to remove, loop through stored routes to make sure it exists
            uint256 j = 0;
            for (; j < receiversStoredLength; ++j) {
                // If route to add is equal to a stored route, remove.
                if (receiverToRemove == messageReceiversStored[j]) {
                    emit MessageReceiverDeleted(messageOrigin, sourceChainSelector, messageType, receiverToRemove);

                    // For each removal, overwrite index to remove and pop last element
                    messageReceiversStored[j] = messageReceiversStored[receiversStoredLength - 1];
                    messageReceiversStored.pop();

                    // Can only have one message route per dest chain selector, when we find it break for loop.
                    break;
                }
            }

            // If we get to the end of the messageReceiversStored array, item to be deleted does not exist.
            if (j == receiversStoredLength) {
                revert Errors.ItemNotFound();
            }
        }
    }

    /// @notice Sets valid sender for source chain
    /// @dev This will be the message proxy contract on the source chain
    /// @dev Used to add and remove source chain senders
    /// @param sourceChainSelector Selector for source chain
    /// @param sourceChainSender Sender from the source chain, MessageProxy contract
    function setSourceChainSenders(
        uint64 sourceChainSelector,
        address sourceChainSender
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Check that source chain selector registered with Chainlink router.  Will differ by chain
        if (sourceChainSender != address(0)) {
            CCUtils.validateChain(IRouterClient(i_ccipRouter), sourceChainSelector);
        }

        emit SourceChainSenderSet(sourceChainSelector, sourceChainSender);
        sourceChainSenders[sourceChainSelector] = sourceChainSender;
    }

    /// @notice Gets all message receivers for origin, source chain, message type
    /// @return receivers address array of the message receivers
    function getMessageReceivers(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) external view returns (address[] memory receivers) {
        bytes32 receiversKey = _getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType);
        receivers = messageReceivers[receiversKey];
    }

    /// =====================================================
    /// Functions - Helpers
    /// =====================================================

    /// @dev Decodes CCUtils.Message struct sent from source chain
    function decodeMessage(bytes memory encodedMessage) private pure returns (CCUtils.Message memory) {
        return abi.decode(encodedMessage, (CCUtils.Message));
    }

    /// @dev Hashes together origin, sourceChainSelector, messageType to get key for destinations
    function _getMessageReceiversKey(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(messageOrigin, sourceChainSelector, messageType));
    }
}
