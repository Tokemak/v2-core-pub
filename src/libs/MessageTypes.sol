// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

library MessageTypes {
    /// @notice LST Base APR snapshots
    bytes32 public constant LST_SNAPSHOT_MESSAGE_TYPE = keccak256("LST_SNAPSHOT");

    /// @notice LST Eth Per Token changes
    bytes32 public constant LST_BACKING_MESSAGE_TYPE = keccak256("LST_BACKING");

    /// @notice Message structure for `LST_BACKING_MESSAGE_TYPE`
    struct LstBackingMessage {
        address token;
        uint208 ethPerToken;
        uint48 timestamp;
    }
}
