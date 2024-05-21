// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { MessageReceiverBase } from "src/receivingRouter/MessageReceiverBase.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";

// solhint-disable func-name-mixedcase

contract MessageReceiverTests is Test, SystemRegistryMocks {
    ISystemRegistry public systemRegistry;
    address public receivingRouter;
    MockMessageReceiverBase public receiverBase;

    constructor() SystemRegistryMocks(vm) { }

    function setUp() public {
        systemRegistry = ISystemRegistry(makeAddr("SYSTEM_REGISTRY"));
        receivingRouter = makeAddr("RECEIVING_ROUTER");
        receiverBase = new MockMessageReceiverBase(systemRegistry);
    }

    function test_State() public {
        assertEq(receiverBase.getSystemRegistry(), address(systemRegistry));
    }

    function test_RevertIf_NotReceivingRouter() public {
        _mockSysRegReceivingRouter(systemRegistry, receivingRouter);
        vm.expectRevert(MessageReceiverBase.NotReceivingRouter.selector);
        receiverBase.onMessageReceive(keccak256("messageType"), abi.encode(1));
    }

    function test_RunsWhenReceivingRouterCall() public {
        _mockSysRegReceivingRouter(systemRegistry, receivingRouter);
        vm.prank(receivingRouter);
        receiverBase.onMessageReceive(keccak256("messageType"), abi.encode(1));
        assertEq(receiverBase.check(), 1);
    }
}

contract MockMessageReceiverBase is MessageReceiverBase, SystemComponent {
    uint256 public check = 0;

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    function _onMessageReceive(bytes32, bytes memory) internal override {
        check++;
    }
}
