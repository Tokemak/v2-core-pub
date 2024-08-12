// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

interface IMessageReceiverBase {
    /// @notice Called by ReceivingRouter.sol on message from ccipRouter that targets inheriting contract.
    /// @param messageType Key for type of message being received.
    /// @param messageNonce Nonce of message sent from L1.
    /// @param message Encoded message from origin contract and chain.
    function onMessageReceive(bytes32 messageType, uint256 messageNonce, bytes memory message) external;
}
