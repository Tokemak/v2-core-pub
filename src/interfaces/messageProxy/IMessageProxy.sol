// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @title Send messages to our systems on other chains
interface IMessageProxy {
    function sendMessage(bytes32 messageType, bytes memory message) external;
}
