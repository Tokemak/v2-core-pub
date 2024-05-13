// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

interface IMessageReceiverBase {
    function onMessageReceive(bytes memory message) external;
}
