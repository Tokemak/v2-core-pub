// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";

/// @title Proxy contract, sits in from of Chainlink CCIP and routes messages to various chains
contract MessageProxy is IMessageProxy, SecurityBase {
    /// =====================================================
    /// Constant Vars
    /// =====================================================

    /// @notice Version of the messages being sent to our receivers
    uint256 public constant VERSION = 1;

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

    /// @notice Data structure going across the wire to destination chain.
    /// Encoded and stored in `data` field of EVM2AnyMessage Chainlink struct.
    struct Message {
        address sender;
        uint256 version;
        uint256 messageTimestamp;
        bytes32 messageType;
        bytes message;
    }

    /// @notice Destination chain to send a message to and the gas required for that chain
    struct MessageRouteConfig {
        uint64 destinationChainSelector;
        uint192 gas;
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

    /// @notice Thrown when not enough fee is left for send.
    error NotEnoughFee(uint256 available, uint256 needed);

    /// @notice Thrown when message data is different on retry, resulting in mismatch hash.
    error MismatchMessageHash(bytes32 storedHash, bytes32 currentHash);

    /// @notice Thrown when registering routes and the given chain id isn't supported CCIP
    error ChainNotSupported(uint64 chainId);

    /// =====================================================
    /// Events
    /// =====================================================

    /// @notice Emitted when message is built to be sent.
    event MessageData(
        bytes32 indexed messageHash, uint256 messageTimestamp, address sender, bytes32 messageType, bytes message
    );

    /// @notice Emitted when a message is sent.
    event MessageSent(uint64 destChainSelector, bytes32 messageHash, bytes32 ccipMessageId);

    /// @notice Emitted when a receiver contract is set for a destination chain
    event ReceiverSet(uint64 destChainSelector, address destinationChainReceiver);

    /// @notice Emitted when a receiver contract is removed
    event ReceiverRemoved(uint64 destChainSelector, address destinationChainReceiver);

    /// @notice Emitted when a message route is added
    event MessageRouteAdded(address sender, bytes32 messageType, uint64 destChainSelector);

    /// @notice Emitted when a message route is removed
    event MessageRouteDeleted(address sender, bytes32 messageType, uint64 destChainSelector);

    /// @notice Emitted when we update the gas sent for a message to a chain
    event GasUpdated(address sender, bytes32 messageType, uint64 destChainSelector, uint192 gas);

    /// =====================================================
    /// Events - Failure
    /// @dev All below events emitted upon message failure in `sendMessage()`
    /// =====================================================

    /// @notice Emitted when a message fails in try-catch.
    event MessageFailed(uint64 destChainId, bytes32 messageHash);

    /// @notice Emitted when message fails due to fee.
    event MessageFailedFee(uint64 destChainId, bytes32 messageHash, uint256 currentBalance, uint256 feeNeeded);

    /// @notice Emitted when a destination chain is not registered
    event DestinationChainNotRegisteredEvent(uint256 destChainId, bytes32 messageHash);

    /// @notice Emitted when message sent in by calculator does not exist
    event MessageZeroLength(address messageSender, bytes32 messageType);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry,
        IRouterClient ccipRouter
    ) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(address(ccipRouter), "ccipRouter");

        routerClient = ccipRouter;
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Sends message to destination chain(s)
    /// @dev Can only be called by calculator.
    /// @dev Can not revert, do not want ability to interrupt calculator snap-shotting on L1
    function sendMessage(bytes32 messageType, bytes memory message) external override {
        // Lookup message routes from _messageRoutes
        MessageRouteConfig[] memory configs = _messageRoutes[msg.sender][messageType];
        uint256 configsLength = configs.length;

        // If there are zero routes, then just return, nothing to do
        // Routes act as our security
        if (configsLength == 0) return;

        uint256 messageTimestamp = block.timestamp;

        // Encode and hash message, set hash to last message for sender and messageType
        bytes memory encodedMessage = encodeMessage(msg.sender, VERSION, messageTimestamp, messageType, message);
        bytes32 messageHash = keccak256(encodedMessage);

        lastMessageSent[msg.sender][messageType] = messageHash;

        emit MessageData(messageHash, messageTimestamp, msg.sender, messageType, message);

        // Loop through configs, attempt to send message to each destination.
        for (uint256 i = 0; i < configsLength; ++i) {
            uint64 destChainSelector = configs[i].destinationChainSelector;
            address destChainReceiver = destinationChainReceivers[destChainSelector];

            // Covers both selector and receiver, cannot set address for zero selector.
            if (destChainReceiver == address(0)) {
                emit DestinationChainNotRegisteredEvent(destChainSelector, messageHash);
                continue;
            }

            // Build ccip message
            Client.EVM2AnyMessage memory ccipMessage = _ccipBuild(destChainReceiver, configs[i].gas, encodedMessage);

            uint256 fee = routerClient.getFee(destChainSelector, ccipMessage);
            uint256 addressBalance = address(this).balance;
            // If we have the balance, try ccip message

            // slither-disable-next-line timestamp
            if (addressBalance >= fee) {
                // Catch any errors thrown from L1 ccip, emit event with information on success or failure
                try routerClient.ccipSend{ value: fee }(destChainSelector, ccipMessage) returns (bytes32 ccipMessageId)
                {
                    // slither-disable-next-line reentrancy-events
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

    /// @notice Retry for multiple messages to multiple destinations per message.
    /// @dev Caller must send in ETH to cover router fees. Cannot use contract balance
    /// @dev Excess ETH is not refunded, use getFee() to calculate needed amount
    function resendLastMessage(RetryArgs[] memory args) external payable hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        // Tracking for fee
        uint256 feeLeft = msg.value;

        // Loop through RetryArgs array.
        for (uint256 i = 0; i < args.length; ++i) {
            // Store vars with multiple usages locally.  `messageRetryTimestamp` not stored due to stack too deep
            RetryArgs memory currentRetry = args[i];
            address msgSender = currentRetry.msgSender;
            bytes32 messageType = currentRetry.messageType;
            bytes memory message = currentRetry.message;

            // Get hash from data passed in, hash from last message, revert if they are not equal.
            bytes32 currentMessageHash = keccak256(
                abi.encode(Message(msgSender, VERSION, currentRetry.messageRetryTimestamp, messageType, message))
            );
            {
                bytes32 storedMessageHash = lastMessageSent[msgSender][messageType];
                if (currentMessageHash != storedMessageHash) {
                    revert MismatchMessageHash(storedMessageHash, currentMessageHash);
                }
            }

            // Loop through and send off to destinations in specific RetryArgs struct, fee dependent.
            for (uint256 j = 0; j < currentRetry.configs.length; ++j) {
                uint64 currentDestChainSelector = currentRetry.configs[j].destinationChainSelector;
                address destChainReceiver = destinationChainReceivers[currentDestChainSelector];

                // Covers destChainSelector being zero as well, cannot set 0 for selector, will always return address(0)
                Errors.verifyNotZero(destChainReceiver, "destChainReceiver");

                Client.EVM2AnyMessage memory ccipMessage =
                    _ccipBuild(destChainReceiver, currentRetry.configs[j].gas, message);

                uint256 fee = routerClient.getFee(currentDestChainSelector, ccipMessage);

                // slither-disable-next-line timestamp
                if (feeLeft < fee) {
                    revert NotEnoughFee(feeLeft, fee);
                }

                // Checked above
                unchecked {
                    feeLeft -= fee;
                }

                // slither-disable-next-line arbitrary-send-eth
                bytes32 ccipMessageId = routerClient.ccipSend{ value: fee }(currentDestChainSelector, ccipMessage);

                // slither-disable-next-line reentrancy-events
                emit MessageSent(currentDestChainSelector, currentMessageHash, ccipMessageId);
            }
        }
    }

    /// @notice Sets our receiver on the destination chain
    /// @param destinationChainSelector CCIP chain id
    /// @param destinationChainReceiver Our receiver contract on the destination chain
    function setDestinationChainReceiver(
        uint64 destinationChainSelector,
        address destinationChainReceiver
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        // Check that we aren't doing cleanup if a chain is deprecated
        if (destinationChainReceiver != address(0)) {
            _verifyValidChain(destinationChainSelector);
        }

        emit ReceiverSet(destinationChainSelector, destinationChainReceiver);

        destinationChainReceivers[destinationChainSelector] = destinationChainReceiver;
    }

    /// @notice Add message routes for sender / messageType
    function addMessageRoutes(
        address sender,
        bytes32 messageType,
        MessageRouteConfig[] memory routes
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        Errors.verifyNotZero(sender, "sender");
        Errors.verifyNotZero(messageType, "messageType");

        uint256 routesLength = routes.length;
        Errors.verifyNotZero(routesLength, "routesLength");

        for (uint256 i = 0; i < routesLength; ++i) {
            uint64 currentDestChainSelector = routes[i].destinationChainSelector;

            _verifyValidChain(currentDestChainSelector);

            Errors.verifyNotZero(uint256(routes[i].gas), "gas");

            // Check that overwrite is not happening.
            MessageRouteConfig[] memory currentStoredRoutes = _messageRoutes[sender][messageType];
            uint256 currentLen = currentStoredRoutes.length;
            for (uint256 j = 0; j < currentLen; ++j) {
                if (currentStoredRoutes[j].destinationChainSelector == currentDestChainSelector) {
                    revert Errors.ItemExists();
                }
            }

            emit MessageRouteAdded(sender, messageType, currentDestChainSelector);
            _messageRoutes[sender][messageType].push(routes[i]);
        }
    }

    /// @notice Remove message routes for sender / messageType
    function removeMessageRoutes(
        address sender,
        bytes32 messageType,
        uint64[] calldata chainSelectors
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        Errors.verifyNotZero(sender, "sender");
        Errors.verifyNotZero(messageType, "messageType");

        uint256 chainLength = chainSelectors.length;
        Errors.verifyNotZero(chainLength, "chainLength");

        MessageRouteConfig[] storage currentStoredRoutes = _messageRoutes[sender][messageType];

        for (uint256 i = 0; i < chainLength; ++i) {
            uint256 currentLen = currentStoredRoutes.length;
            if (currentLen == 0) {
                revert Errors.ItemNotFound();
            }
            // For each route we want to remove, loop through stored routes.
            uint256 j = 0;
            for (; j < currentLen; ++j) {
                // If route to add is equal to a stored route, remove.
                if (chainSelectors[i] == currentStoredRoutes[j].destinationChainSelector) {
                    emit MessageRouteDeleted(sender, messageType, chainSelectors[i]);

                    // For each route, record index of storage array that was deleted.
                    currentStoredRoutes[j] = currentStoredRoutes[currentStoredRoutes.length - 1];
                    currentStoredRoutes.pop();

                    // Can only have one message route per dest chain selector, when we find it break for loop.
                    break;
                }
            }

            // If we get to the end of the currentStoredRoutes array, item to be deleted does not exist.
            if (j == currentLen) {
                revert Errors.ItemNotFound();
            }
        }
    }

    /// @notice Updates the gas we'll send for this message route
    function setGasForRoute(
        address messageSender,
        bytes32 messageType,
        uint64 chainId,
        uint192 gas
    ) external hasRole(Roles.MESSAGE_PROXY_ADMIN) {
        Errors.verifyNotZero(messageSender, "sender");
        Errors.verifyNotZero(messageType, "messageType");
        Errors.verifyNotZero(gas, "gas");

        MessageRouteConfig[] storage currentStoredRoutes = _messageRoutes[messageSender][messageType];
        uint256 routeLength = currentStoredRoutes.length;

        uint256 i = 0;
        for (; i < routeLength; ++i) {
            if (currentStoredRoutes[i].destinationChainSelector == chainId) {
                currentStoredRoutes[i].gas = gas;
                emit GasUpdated(messageSender, messageType, chainId, gas);
                break;
            }
        }

        if (i == routeLength) {
            revert Errors.ItemNotFound();
        }
    }

    function encodeMessage(
        address sender,
        uint256 version,
        uint256 messageTimestamp,
        bytes32 messageType,
        bytes memory message
    ) public pure returns (bytes memory) {
        return abi.encode(
            Message({
                sender: sender,
                version: version,
                messageTimestamp: messageTimestamp,
                messageType: messageType,
                message: message
            })
        );
    }

    /// @notice Estimate fees off-chain for purpose of retries
    function getFee(
        address messageSender,
        bytes32 messageType,
        bytes memory message
    ) external view returns (uint64[] memory chains, uint256[] memory fees) {
        MessageRouteConfig[] memory configs = _messageRoutes[messageSender][messageType];
        uint256 len = configs.length;

        chains = new uint64[](len);
        fees = new uint256[](len);

        bytes memory encodedMessage = encodeMessage(messageSender, VERSION, block.timestamp, messageType, message);

        for (uint256 i = 0; i < len; ++i) {
            uint64 destChainSelector = configs[i].destinationChainSelector;
            address destChainReceiver = destinationChainReceivers[destChainSelector];

            // Build message for fee.
            Client.EVM2AnyMessage memory ccipFeeMessage = _ccipBuild(destChainReceiver, configs[i].gas, encodedMessage);

            chains[i] = destChainSelector;
            fees[i] = routerClient.getFee(destChainSelector, ccipFeeMessage);
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
    /// Functions - Private Helpers
    /// =====================================================

    /// @notice Builds Chainlink specified message to send to destination chain.
    function _ccipBuild(
        address destinationChainReceiver,
        uint256 gas,
        bytes memory message
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(destinationChainReceiver),
            data: message, // Encoded Message struct
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0), // Native Eth
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: gas }))
        });
    }

    /// @notice Verify the given chain id is valid in CCIP
    /// @dev Reverts when not valid
    function _verifyValidChain(uint64 chain) private view {
        if (!routerClient.isChainSupported(chain)) {
            revert ChainNotSupported(chain);
        }
    }
}
