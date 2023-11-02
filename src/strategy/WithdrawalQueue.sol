// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17; // their version was using 8.12?

import { StructuredLinkedList } from "src/strategy/StructuredLinkedList.sol";

// https://github.com/Layr-Labs/eigenlayer-contracts/blob/master/src/contracts/libraries/StructuredLinkedList.sol
library WithdrawalQueue {
    using StructuredLinkedList for StructuredLinkedList.List;

    error CannotInsertZeroAddress();
    error UnexpectedNodeRemoved();
    error AddToHeadFailed();
    error AddToTailFailed();

    function _addressToUint(address addr) internal pure returns (uint256) {
        return uint256(uint160(addr));
    }

    function _uintToAddress(uint256 x) internal pure returns (address) {
        return address(uint160(x));
    }

    /// @notice Returns true if the address is in the queue.
    function addressExists(StructuredLinkedList.List storage queue, address addr) public view returns (bool) {
        return StructuredLinkedList.nodeExists(queue, _addressToUint(addr));
    }

    /// @notice Returns the current head.
    function peekHead(StructuredLinkedList.List storage queue) public view returns (address) {
        return _uintToAddress(StructuredLinkedList.getHead(queue));
    }

    /// @notice Returns the current tail.
    function peekTail(StructuredLinkedList.List storage queue) public view returns (address) {
        return _uintToAddress(StructuredLinkedList.getTail(queue));
    }

    /// @notice remove address toRemove from queue if it exists.
    function popAddress(StructuredLinkedList.List storage queue, address toRemove) public {
        uint256 addrAsUint = _addressToUint(toRemove);
        uint256 _removedNode = StructuredLinkedList.remove(queue, addrAsUint);
        if (!((_removedNode == addrAsUint) || (_removedNode == 0))) {
            revert UnexpectedNodeRemoved();
        }
    }

    /// @notice returns true if there are no addresses in queue.
    function isEmpty(StructuredLinkedList.List storage queue) public view returns (bool) {
        return !StructuredLinkedList.listExists(queue);
    }

    /// @notice if addr in queue, move it to the top
    // if addr not in queue, add it to the top of the queue.
    // if queue is empty, make a new queue with addr as the only node
    function addToHead(StructuredLinkedList.List storage queue, address addr) public {
        if (addr == address(0)) {
            revert CannotInsertZeroAddress();
        }
        popAddress(queue, addr);
        bool success = StructuredLinkedList.pushFront(queue, _addressToUint(addr));
        if (!success) {
            revert AddToHeadFailed();
        }
    }

    /// @notice if addr in queue, move it to the end
    // if addr not in queue, add it to the end of the queue.
    // if queue is empty, make a new queue with addr as the only node
    function addToTail(StructuredLinkedList.List storage queue, address addr) public {
        if (addr == address(0)) {
            revert CannotInsertZeroAddress();
        }

        popAddress(queue, addr);
        bool success = StructuredLinkedList.pushBack(queue, _addressToUint(addr));
        if (!success) {
            revert AddToTailFailed();
        }
    }
}
