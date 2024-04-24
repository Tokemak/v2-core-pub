// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";
import { SystemSecurity, ISystemRegistry } from "src/security/SystemSecurity.sol";
import { Roles } from "src/libs/Roles.sol";

import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

/// @title Proxy contract, sits in from of Chainlink ccip and routes messages to various destinations on L2
contract MessageProxy is IMessageProxy, SystemSecurity {
    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice Chainlink router instance.
    IRouterClient public immutable routerClient;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Receiver contracts on the destination chains
    /// @dev mapping is destinationChainSelector -> our receiver contract
    mapping(uint64 => address) public destinationChainReceivers;

    /// @notice Hashing of last message sent for sender address and messageType
    /// @dev mapping is msg.sender -> messageType -> messageHash.
    mapping(address => mapping(bytes32 => bytes32)) public lastMessageSent;

    /// =====================================================
    /// Private Vars
    /// =====================================================

    /// @notice Routes configured for a message and sender
    /// @dev mapping is msg.sender -> messageType -> routes. Exposed via getMessageRoutes()
    mapping(address => mapping(bytes32 => MessageRouteConfig[])) private _messageRoutes;

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @notice Destination chain to send a message to and the gas required for that chain
    struct MessageRouteConfig {
        uint64 destinationChainSelector;
        uint192 gasL2;
    }

    /// @notice Arguments used to resend the last message for a sender + type
    struct RetryArgs {
        address msgSender;
        bytes32 messageType;
        uint256 messageRetryTimestamp; // Timestamp of original message, emitted in `MessageData` event.
        bytes message;
        MessageRouteConfig[] configs;
    }

    /// =====================================================
    /// Errors
    /// =====================================================

    /// @notice Thrown when not enough fee is left for L2 send.
    error NotEnoughFee(uint256 available, uint256 needed);

    /// @notice Thrown when message data is different on retry, resulting in mismatch hash.
    error MismatchMessageHash(bytes32 storedHash, bytes32 currentHash);

    /// =====================================================
    /// Events
    /// =====================================================

    /// @notice Emitted when message is built to be sent.
    event MessageData(
        bytes32 indexed messageHash, uint256 messageTimestamp, address sender, bytes32 messageType, bytes message
    );

    /// @notice Emitted when a message is sent.
    event MessageSent(uint64 destChainSelector, bytes32 messageHash, bytes32 ccipMessageId);

    /// @notice Emitted when a receiver contract is added for a destination.
    event RecieverAdded(uint64 destinationChainSelector, address destinationChainReceiver);

    /// @notice Emitted when a receiver contract is removed
    event ReceiverRemoved(uint64 destinationChainSelector, address destinationChainReceiver);

    /// @notice Emitted when a message route is added
    event MessageRouteAdded(address sender, bytes32 messageType, uint256 destChainSelector);

    /// @notice Emitted when a message route is removed
    event MessageRouteDeleted(address sender, bytes32 messageType, uint256 destChainSelector);

    /// =====================================================
    /// Events - Failure
    /// @dev All below events emitted upon message failure in `sendMessage()`
    /// =====================================================

    /// @notice Emitted when a message fails in try-catch.
    event MessageFailed(uint64 destChainId, bytes32 messageHash);

    /// @notice Emitted when message fails due to fee.
    event MessageFailedFee(uint64 destChainId, bytes32 messageHash, uint256 currentBalance, uint256 feeNeeded);

    /// @notice Emitted when a destination chain is not registered
    event DestinationChainNotRegisteredEvent(uint256 destChainId);

    /// @notice Emitted when message sent in by calculator does not exist
    event MessageZeroLength(address messageSender, bytes32 messageType);

    /// =====================================================
    /// Modifiers
    /// =====================================================

    /// @notice Checks to ensure that caller is calculator registered in system.
    modifier onlyCalculator() {
        bytes32 aprId = IStatsCalculator(msg.sender).getAprId();
        // No check needed, reverts on zero address in StatsCalculatorRegistry
        address(systemRegistry.statsCalculatorRegistry().getCalculator(aprId));
        _;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(IRouterClient ccipRouter, ISystemRegistry _systemRegistry) SystemSecurity(_systemRegistry) {
        Errors.verifyNotZero(address(ccipRouter), "router");

        routerClient = ccipRouter;
    }

    /// =====================================================
    /// Functions - Setters
    /// =====================================================

    /// @notice Sets destinations on L2s.  Handles both adds and removes
    function setDestinationChainReceivers(
        uint64 destinationChainSelector,
        address destinationChainReceiver,
        bool add
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        Errors.verifyNotZero(destinationChainSelector, "destinationChainSelector");

        if (add) {
            Errors.verifyNotZero(destinationChainReceiver, "destinationChainReceiver");

            // Ensure that we are not overwriting anything
            if (destinationChainReceivers[destinationChainSelector] != address(0)) {
                revert Errors.MustBeZero();
            }

            emit RecieverAdded(destinationChainSelector, destinationChainReceiver);
            destinationChainReceivers[destinationChainSelector] = destinationChainReceiver;
        } else {
            // Store to avoid multiple storage reads.
            address receiverToRemove = destinationChainReceivers[destinationChainSelector];
            // Ensure that something exists for us to delete
            if (receiverToRemove == address(0)) {
                revert Errors.MustBeSet();
            }

            emit ReceiverRemoved(destinationChainSelector, receiverToRemove);
            delete destinationChainReceivers[destinationChainSelector];
        }
    }

    /**
     * NOTES
     *  Think that delete path here may be able to be optimized a bit, something around if two currentStored and
     *    routes is same length we don't have to fill in other elements, can just pop.  Still needs checks for
     *    correct route etc.
     *
     * QUESTIONS
     *  Any issue with lengths of currentStored and routes on remove? One being greater than other etc.
     *  Check for routes length > storage length? This will already revert because item will not exist, so maybe not
     */
    /// @notice Sets message routes for sender / messageType.  Handles both adds and removes
    function setMessageRoutes(
        address sender,
        bytes32 messageType,
        MessageRouteConfig[] memory routes,
        bool add
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        Errors.verifyNotZero(sender, "sender");
        Errors.verifyNotZero(messageType, "messageType");

        uint256 routesLength = routes.length;
        Errors.verifyNotZero(routesLength, "routesLength");

        if (add) {
            for (uint256 i = 0; i < routes.length; ++i) {
                uint256 currentDestChainSelector = routes[i].destinationChainSelector;

                Errors.verifyNotZero(currentDestChainSelector, "currentRouteDestChainSelector");
                Errors.verifyNotZero(uint256(routes[i].gasL2), "routes[i].gas");

                // Check that overwrite is not happening.
                MessageRouteConfig[] memory currentStoredRoutes = _messageRoutes[sender][messageType];
                for (uint256 j = 0; j < currentStoredRoutes.length; ++j) {
                    if (currentStoredRoutes[j].destinationChainSelector == currentDestChainSelector) {
                        revert Errors.ItemExists();
                    }
                }

                emit MessageRouteAdded(sender, messageType, currentDestChainSelector);
                _messageRoutes[sender][messageType].push(routes[i]);
            }
        } else {
            MessageRouteConfig[] storage currentStoredRoutes = _messageRoutes[sender][messageType];

            // Store indexes deleted in storage array for replacement later.
            uint256[] memory deletedIxs = new uint256[](routes.length);

            for (uint256 i = 0; i < routes.length; ++i) {
                // For each route we want to remove, loop through stored routes.
                for (uint256 j = 0; j < currentStoredRoutes.length; ++j) {
                    // If route to add is equal to a stored route, remove.
                    if (routes[i].destinationChainSelector == currentStoredRoutes[j].destinationChainSelector) {
                        emit MessageRouteDeleted(sender, messageType, routes[i].destinationChainSelector);

                        // For each route, record index of storage array that was deleted.
                        deletedIxs[i] = j;
                        delete currentStoredRoutes[j];

                        // Can only have one message route per dest chain selector, when we find it break for loop.
                        break;
                    }

                    // If we get to the end of the currentStoredRoutes array, item to be deleted does not exist.
                    if (j == currentStoredRoutes.length - 1) {
                        revert Errors.ItemNotFound();
                    }
                }
            }

            // Fill in empty slots in storage.
            for (uint256 i = 0; i < deletedIxs.length; ++i) {
                // Array is shrinking and storage updating as loop iterates, - 1 will always give the last element.
                uint256 elementToShiftIx = currentStoredRoutes.length - 1;

                // If element to shift is not zeroed, move to deleted ix.  Implicitly does not move but deletes zeroed
                // elements at elementToShiftIx.
                if (currentStoredRoutes[elementToShiftIx].destinationChainSelector != 0) {
                    currentStoredRoutes[deletedIxs[i]] = currentStoredRoutes[elementToShiftIx];
                }
                currentStoredRoutes.pop();
            }
        }
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Sends message to L2
    /// @dev Can only be called by calculator.
    /// @dev Can not revert, do not want ability to interrupt calculator snapshotting on L1
    function sendMessage(bytes32 messageType, bytes memory message) external override onlyCalculator {
        // Lookup message routes from _messageRoutes
        MessageRouteConfig[] memory configs = _messageRoutes[msg.sender][messageType];
        uint256 configsLength = configs.length;

        // If there are zero routes, then just return, nothing to do
        // Routes act as our security
        if (configsLength == 0) return;
        if (message.length == 0) {
            emit MessageZeroLength(msg.sender, messageType);
            return;
        }

        uint256 messageTimestamp = block.timestamp;

        // Encode and hash message, set hash to last message for sender and messageType
        bytes memory encodedMessage = abi.encode(Message(msg.sender, 1, messageTimestamp, messageType, message));
        bytes32 messageHash = keccak256(encodedMessage);
        lastMessageSent[msg.sender][messageType] = messageHash;

        emit MessageData(messageHash, messageTimestamp, msg.sender, messageType, message);

        // Loop through configs, attempt to send message to each destination.
        for (uint256 i = 0; i < configsLength; ++i) {
            uint64 destChainSelector = configs[i].destinationChainSelector;
            address destChainReceiver = destinationChainReceivers[destChainSelector];

            // Covers both selector and receiver, cannot set address for zero selector.
            if (destChainReceiver == address(0)) {
                emit DestinationChainNotRegisteredEvent(destChainSelector);
                continue;
            }

            // Build ccip message
            Client.EVM2AnyMessage memory ccipMessage = _ccipBuild(destChainReceiver, configs[i].gasL2, encodedMessage);

            uint256 fee = routerClient.getFee(destChainSelector, ccipMessage);
            uint256 addressBalance = address(this).balance;
            // If we have the balance, try ccip message
            if (addressBalance >= fee) {
                // Catch any errors thrown from L1 ccip, emit event with information on success or failure
                try routerClient.ccipSend{ value: fee }(destChainSelector, ccipMessage) returns (bytes32 ccipMessageId)
                {
                    emit MessageSent(destChainSelector, messageHash, ccipMessageId);
                } catch {
                    emit MessageFailed(destChainSelector, messageHash);
                }
            } else {
                // If we do not have balance, emit message telling so.
                emit MessageFailedFee(destChainSelector, messageHash, addressBalance, fee);
            }
        }
    }

    /**
     * QUESTIONS
     * Does `lastMessageSent` need to be cleared? Don't think that there is any reason to unless we want to stop
     *    messages from being resent.  However, any message resent would have to be exactly the same, makes delete feel
     *    like waste
     * If it does, need to account for a half done situation where some dest chains receive message and others don't
     *
     * Checks needed for `currentRetry`? Think we're covered by hash and message route setting flow.
     *
     * Do we want to move towards standard reverting here? Idea behind current is that we get some messages off,
     *    others do not
     */
    /// @notice Retry for multiple messages to multiple destinations per message.
    /// @dev Caller must send in ETH to cover router fees. Cannot use contract balance
    function resendLastMessage(RetryArgs[] memory args) external payable hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        // Tracking for fee
        uint256 feeLeft = msg.value;

        // Loop through RetryArgs array.
        for (uint256 i = 0; i < args.length; ++i) {
            // Store vars with multiple usages locally.  `messageRetryTimestamp` not stored due to stack too deep
            RetryArgs memory currentRetry = args[i];
            address calculatorMessageSender = currentRetry.msgSender;
            bytes32 messageType = currentRetry.messageType;
            bytes memory message = currentRetry.message;

            // Get hash from data passed in, hash from last message, revert if they are not equal.
            bytes32 currentMessageHash = keccak256(
                abi.encode(
                    Message(calculatorMessageSender, 1, currentRetry.messageRetryTimestamp, messageType, message)
                )
            );
            bytes32 storedMessageHash = lastMessageSent[calculatorMessageSender][messageType];
            if (currentMessageHash != storedMessageHash) {
                revert MismatchMessageHash(storedMessageHash, currentMessageHash);
            }

            emit MessageData(
                currentMessageHash, currentRetry.messageRetryTimestamp, calculatorMessageSender, messageType, message
            );

            // Loop through and send off to destinations in specific RetryArgs struct, fee dependent.
            for (uint256 j = 0; j < currentRetry.configs.length; ++j) {
                uint64 currentDestChainSelector = currentRetry.configs[j].destinationChainSelector;
                address destChainReceiver = destinationChainReceivers[currentDestChainSelector];

                // Covers destChainSelector being zero as well, cannot set 0 for selector, will always return address(0)
                Errors.verifyNotZero(destChainReceiver, "destChainReceiver");

                Client.EVM2AnyMessage memory ccipMessage =
                    _ccipBuild(destChainReceiver, currentRetry.configs[j].gasL2, message);

                uint256 fee = routerClient.getFee(currentDestChainSelector, ccipMessage);

                // If feeLeft less than fee, emit message, set fee to 0 to break outer loop, break inner loop.
                if (feeLeft < fee) {
                    emit MessageFailedFee(currentDestChainSelector, currentMessageHash, feeLeft, fee);
                    feeLeft = 0;
                    break;
                }

                // Checked above
                unchecked {
                    feeLeft -= fee;
                }

                bytes32 ccipMessageId = routerClient.ccipSend{ value: fee }(currentDestChainSelector, ccipMessage);
                emit MessageSent(currentDestChainSelector, currentMessageHash, ccipMessageId);
            }
            // If no fee left, exit loop
            if (feeLeft == 0) {
                break;
            }
        }
    }

    /// @notice Estimate fees off-chain for purpose of retries
    function getFee(
        address messageSender,
        bytes32 messageType,
        bytes memory message
    ) external view returns (uint64[] memory chainId, uint256[] memory gas) {
        MessageRouteConfig[] memory configs = _messageRoutes[messageSender][messageType];
        uint256 configsLength = configs.length;

        Errors.verifyNotZero(configsLength, "configsLength");
        Errors.verifyNotZero(message.length, "message.length");

        bytes memory encodedMessage = abi.encode(Message(messageSender, 1, block.timestamp, messageType, message));

        for (uint256 i = 0; i < configsLength; ++i) {
            uint64 destChainSelector = configs[i].destinationChainSelector;
            address destChainReceiver = destinationChainReceivers[destChainSelector];

            Errors.verifyNotZero(destChainReceiver, "destChainReceiver");

            chainId[i] = destChainSelector;

            // Build message for fee.
            Client.EVM2AnyMessage memory ccipFeeMessage =
                _ccipBuild(destChainReceiver, configs[i].gasL2, encodedMessage);

            gas[i] = routerClient.getFee(destChainSelector, ccipFeeMessage);
        }
    }

    /// @notice Returns all message routes for sender and messageType.
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

    /// =====================================================
    /// Functions - Receive
    /// =====================================================

    receive() external payable { }

    /// =====================================================
    /// Functions - Private
    /// =====================================================

    /// @notice Builds Chainlink specified message to send to L2.
    function _ccipBuild(
        address destinationChainReceiver,
        uint256 gasLimitL2,
        bytes memory message
    ) private pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(destinationChainReceiver),
            data: message, // Encoded Message struct
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0), // Native Eth
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: gasLimitL2 }))
        });
    }
}
