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

contract ReceivingRouter is CCIPReceiver, SystemComponent, SecurityBase {
    /// =====================================================
    /// Public vars
    /// =====================================================

    /// @notice keccack256(address origin, uint256 sourceChainSelector, bytes32 messageType) => address[]
    mapping(bytes32 => address[]) public messageReceivers;

    /// @notice uint64 sourceChainSelector => address sender
    /// @dev The contract that sends the message across chains
    mapping(uint64 => address) public sourceChainSenders;

    /// @notice address sender => bytes32 messageType => bytes32 hash
    mapping(address => mapping(bytes32 => bytes32)) public lastMessageSent;

    /// =====================================================
    /// Structs
    /// =====================================================

    struct ResendArgsReceivingChain {
        address messageOrigin;
        bytes32 messageType;
        uint256 messageRetryTimestamp;
        uint64 sourceChainSelector;
        bytes message;
        address[] messageReceivers;
    }

    /// =====================================================
    /// Errors
    /// =====================================================

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

    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);

    event SourceChainSenderDeleted(uint64 sourceChainSelector);

    event MessageReceived(address messageReceiver);

    event MessageReceivedOnResend(address currentReceiver, bytes message);

    event MessageReceiverAdded(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToAdd
    );

    event MessageReceiverDeleted(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToRemove
    );

    /// =====================================================
    /// Failure Events
    /// =====================================================

    event InvalidSenderFromSource(uint256 sourceChainSelector, address sourceChainSender);

    event NoMessageReceiversRegistered(address messageOrigin, bytes32 messageType);

    event MessageFailed(address messageReceiver);

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
    function _ccipReceive(Client.Any2EVMMessage memory ccipMessage) internal override {
        uint64 sourceChainSelector = ccipMessage.sourceChainSelector;
        address proxySender = abi.decode(ccipMessage.sender, (address));
        bytes memory messageData = ccipMessage.data;

        if (sourceChainSenders[sourceChainSelector] != proxySender) {
            emit InvalidSenderFromSource(sourceChainSelector, proxySender);
            return;
        }

        CCUtils.Message memory messageFromProxy = decodeMessage(messageData);
        uint256 messageProxyVersion = messageFromProxy.version;
        uint256 recevingRouterVersion = CCUtils.getVersion();
        if (messageProxyVersion != recevingRouterVersion) {
            revert CCUtils.VersionMismatch(messageProxyVersion, recevingRouterVersion);
        }

        address origin = messageFromProxy.messageOrigin;
        bytes32 messageType = messageFromProxy.messageType;
        bytes memory message = messageFromProxy.message;

        address[] memory messageReceiversForRoute =
            messageReceivers[_getMessageReceiversKey(origin, sourceChainSelector, messageType)];
        uint256 messageReceiversForRouteLength = messageReceiversForRoute.length;

        if (messageReceiversForRouteLength == 0) {
            emit NoMessageReceiversRegistered(origin, messageType);
            return;
        }

        // Hash encoded Message struct.
        bytes32 messageHash = keccak256(messageData);
        lastMessageSent[origin][messageType] = messageHash;

        emit MessageData(
            messageHash,
            messageFromProxy.messageTimestamp,
            origin,
            messageType,
            ccipMessage.messageId,
            sourceChainSelector,
            message
        );

        for (uint256 i = 0; i < messageReceiversForRouteLength; ++i) {
            address currentMessageReceiver = messageReceiversForRoute[i];
            try IMessageReceiverBase(currentMessageReceiver).onMessageReceive(message) {
                emit MessageReceived(currentMessageReceiver);
            } catch {
                emit MessageFailed(currentMessageReceiver);
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
            address[] memory resendMessageReceivers = currentResend.messageReceivers;
            uint256 resendMessageReceiversLength = resendMessageReceivers.length;

            Errors.verifyNotZero(resendMessageReceiversLength, "resendMessageReceiversLength");

            // Get hash from data passed in, hash from last message, revert if they are not equal.
            bytes32 currentMessageHash = keccak256(
                CCUtils.encodeMessage(messageOrigin, currentResend.messageRetryTimestamp, messageType, message)
            );

            {
                bytes32 storedMessageHash = lastMessageSent[messageOrigin][messageType];
                if (currentMessageHash != storedMessageHash) {
                    revert CCUtils.MismatchMessageHash(storedMessageHash, currentMessageHash);
                }
            }

            address[] memory storedMessageReceiversForKey =
            // solhint-disable-next-line max-line-length
             messageReceivers[_getMessageReceiversKey(messageOrigin, currentResend.sourceChainSelector, messageType)];
            uint256 storedReceiversLength = storedMessageReceiversForKey.length;
            Errors.verifyNotZero(storedReceiversLength, "storedReceiversLength");

            // Loop through and send messages.
            for (uint256 j = 0; j < resendMessageReceiversLength; ++j) {
                address currentReceiver = resendMessageReceivers[j];
                Errors.verifyNotZero(currentReceiver, "currentReceiver");

                // Checking that message receiver exists in our routing information.
                for (uint256 k = 0; k < storedReceiversLength; ++k) {
                    if (currentReceiver == storedMessageReceiversForKey[k]) {
                        break;
                    }
                    if (k == storedReceiversLength) {
                        revert MessageReceiverDoesNotExist(currentReceiver);
                    }
                }

                emit MessageReceivedOnResend(currentReceiver, message);
                IMessageReceiverBase(currentReceiver).onMessageReceive(message);
            }
        }
    }

    function setMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToSet
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        Errors.verifyNotZero(messageOrigin, "messageOrigin");
        Errors.verifyNotZero(messageType, "messageType");

        uint256 messageReceiversToSetLength = messageReceiversToSet.length;
        Errors.verifyNotZero(messageReceiversToSetLength, "messageReceiversToSetLength");

        // Handles valid chain selector and chain being set.
        if (sourceChainSenders[sourceChainSelector] == address(0)) {
            revert CCUtils.ChainNotSupported(sourceChainSelector);
        }

        address[] memory currentStoredMessageReceivers =
            messageReceivers[_getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType)];
        uint256 currentStoredMessageReceiversLength = currentStoredMessageReceivers.length;
        for (uint256 i = 0; i < messageReceiversToSetLength; ++i) {
            address receiverToAdd = messageReceiversToSet[i];
            Errors.verifyNotZero(receiverToAdd, "receiverToAdd");

            // TODO: Bug here, will not update
            if (currentStoredMessageReceiversLength > 0) {
                for (uint256 j = 0; j < currentStoredMessageReceiversLength; ++j) {
                    if (receiverToAdd == currentStoredMessageReceivers[j]) {
                        revert Errors.ItemExists();
                    }
                }
            }

            emit MessageReceiverAdded(messageOrigin, sourceChainSelector, messageType, receiverToAdd);
            messageReceivers[_getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType)].push(
                receiverToAdd
            );
        }
    }

    function removeMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToRemove
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        uint256 messageReceiversToRemoveLength = messageReceiversToRemove.length;
        Errors.verifyNotZero(messageReceiversToRemoveLength, "messageReceiversToRemoveLength");

        address[] storage messageReceiversStored =
            messageReceivers[_getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType)];

        for (uint256 i = 0; i < messageReceiversToRemoveLength; ++i) {
            uint256 receiversStoredLength = messageReceiversStored.length;
            address receiverToRemove = messageReceiversToRemove[i];
            if (receiversStoredLength == 0) {
                revert Errors.ItemNotFound();
            }
            // For each route we want to remove, loop through stored routes.
            uint256 j = 0;
            for (; j < receiversStoredLength; ++j) {
                // If route to add is equal to a stored route, remove.
                if (receiverToRemove == messageReceiversStored[j]) {
                    emit MessageReceiverDeleted(messageOrigin, sourceChainSelector, messageType, receiverToRemove);

                    // For each route, record index of storage array that was deleted.
                    messageReceiversStored[j] = messageReceiversStored[receiversStoredLength - 1];
                    messageReceiversStored.pop();

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

    /// =====================================================
    /// Functions - Helpers
    /// =====================================================

    function decodeMessage(bytes memory encodedMessage) private pure returns (CCUtils.Message memory) {
        return abi.decode(encodedMessage, (CCUtils.Message));
    }

    /// @dev Hashes together address origin, uint256 sourceChainSelector, bytes32 messageType to get key for
    /// destinations.
    function _getMessageReceiversKey(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(messageOrigin, sourceChainSelector, messageType));
    }
}
