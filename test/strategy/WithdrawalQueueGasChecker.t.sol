// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { WithdrawalQueue } from "src/strategy/WithdrawalQueue.sol";
import { StructuredLinkedList } from "src/strategy/StructuredLinkedList.sol";

// forge test -vvv --match-path test/strategy/WithdrawalQueue.t.sol

// solhint-disable func-name-mixedcase
contract WithdrawalQueueGasChecker is Test {
    using StructuredLinkedList for StructuredLinkedList.List;

    StructuredLinkedList.List private emptyQueue;
    StructuredLinkedList.List private oneItemQueue;
    StructuredLinkedList.List private fullQueue;

    address private constant _NULL = address(uint160(0));

    address private constant DESTINATION1 = 0x1111111111111111111111111111111111111111;
    address private constant DESTINATION2 = 0x2222222222222222222222222222222222222222;
    address private constant DESTINATION3 = 0x3333333333333333333333333333333333333333;
    address private constant DESTINATION4 = 0x4444444444444444444444444444444444444444;
    address private constant DESTINATION5 = 0x5555555555555555555555555555555555555555;

    function setUp() public {
        WithdrawalQueue.addToTail(oneItemQueue, DESTINATION1);

        WithdrawalQueue.addToTail(fullQueue, DESTINATION1);
        WithdrawalQueue.addToTail(fullQueue, DESTINATION2);
        WithdrawalQueue.addToTail(fullQueue, DESTINATION3);
    }

    // ############## Init tests ##################
    function test_init_addToHead_from_empty() public {
        WithdrawalQueue.addToHead(emptyQueue, DESTINATION1);
    }

    function test_init_addToTail_from_empty() public {
        WithdrawalQueue.addToTail(emptyQueue, DESTINATION1);
    }

    // ############## Pop tests #################

    function test_popAddress_notExistingAddress_empty() public {
        WithdrawalQueue.popAddress(emptyQueue, DESTINATION3);
    }

    function test_popAddress_notExistingAddress_full() public {
        WithdrawalQueue.popAddress(fullQueue, DESTINATION5);
    }

    function test_popAddress_existing_address_top() public {
        WithdrawalQueue.popAddress(fullQueue, DESTINATION1);
    }

    function test_popAddress_existing_address_middle() public {
        WithdrawalQueue.popAddress(fullQueue, DESTINATION2);
    }

    function test_popAddress_existing_address_bottom() public {
        WithdrawalQueue.popAddress(fullQueue, DESTINATION3);
    }

    function test_popAddress_last_item() public {
        WithdrawalQueue.popAddress(oneItemQueue, DESTINATION1);
    }

    // ################# PEEK ############################

    // peek is 5650 +- 100.
    // It does not seem to matter if there is data in the queue or not

    function test_addressExists_True() public view {
        WithdrawalQueue.addressExists(fullQueue, DESTINATION1);
    }

    function test_addressExists_False() public view {
        WithdrawalQueue.addressExists(fullQueue, DESTINATION5);
    }

    function test_peekHead_someValues() public view {
        WithdrawalQueue.peekHead(fullQueue);
    }

    function test_peekHead_noValues() public view {
        WithdrawalQueue.peekHead(emptyQueue);
    }

    function test_peekTail_someValues() public view {
        WithdrawalQueue.peekTail(fullQueue);
    }

    function test_peekTail_noValues() public view {
        WithdrawalQueue.peekTail(emptyQueue);
    }

    // ################## Add new value to queue with some items ###############
    function test_addToTail_newValue_fullQueue() public {
        WithdrawalQueue.addToTail(fullQueue, DESTINATION5);
    }

    function test_addToHead_newValue_fullQueue() public {
        WithdrawalQueue.addToHead(fullQueue, DESTINATION5);
    }

    // ################## Permute tests. Move around an existing value ###############
    // These are the most common operations

    // move a value 36k gas
    // move a value from where it is to where it already was 15k gas

    function test_permute_addToTail() public {
        WithdrawalQueue.addToTail(fullQueue, DESTINATION2);
    }

    function test_permute_addToHead() public {
        WithdrawalQueue.addToHead(fullQueue, DESTINATION2);
    }

    function test_permute_addToTail_from_tail() public {
        WithdrawalQueue.addToTail(fullQueue, DESTINATION3);
    }

    function test_permute_addToHead_from_head() public {
        WithdrawalQueue.addToHead(fullQueue, DESTINATION1);
    }
}
