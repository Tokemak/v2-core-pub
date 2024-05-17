// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test, Vm } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ReceivingRouter } from "src/receivingRouter/ReceivingRouter.sol";
import { CrossChainMessagingUtilities as CCUtils } from "src/libs/CrossChainMessagingUtilities.sol";
import { MessageReceiverBase } from "src/receivingRouter/MessageReceiverBase.sol";
import { Errors } from "src/utils/Errors.sol";

// solhint-disable func-name-mixedcase,contract-name-camelcase

contract ReceivingRouterTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry internal _systemRegistry;
    IAccessController internal _accessController;
    IRouterClient internal _routerClient;

    ReceivingRouter internal _router;

    error InvalidRouter(address messageSender);

    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);
    event MessageReceiverAdded(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address receiverToAdd
    );
    event MessageReceiverDeleted(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToRemove
    );
    event InvalidSenderFromSource(
        uint256 sourceChainSelector, address sourceChainSender, address sourceChainSenderRegistered
    );
    event MessageVersionMismatch(uint256 sourceVersion, uint256 receiverVersion);
    event MessageData(
        bytes32 indexed messageHash,
        uint256 messageTimestamp,
        address messageOrigin,
        bytes32 messageType,
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        bytes message
    );
    event NoMessageReceiversRegistered(address messageOrigin, bytes32 messageType, uint64 sourceChainSelector);
    event MessageReceived(address messageReceiver);
    event MessageFailed(address messageReceiver);
    event MessageReceivedOnResend(address currentReceiver, bytes message);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() public {
        _systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        _accessController = IAccessController(makeAddr("accessController"));
        _routerClient = IRouterClient(makeAddr("routerClient"));

        _mockSysRegAccessController(_systemRegistry, address(_accessController));
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        _router = new ReceivingRouter(address(_routerClient), _systemRegistry);
    }

    function test_SetUpState() public {
        assertEq(_router.getSystemRegistry(), address(_systemRegistry));
        assertEq(_router.getRouter(), address(_routerClient));
    }

    function _mockRouterIsChainSupported(uint64 chainId, bool supported) internal {
        vm.mockCall(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.isChainSupported.selector, chainId),
            abi.encode(supported)
        );
    }

    function _mockIsRouterManager(address user, bool isAdmin) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.RECEIVING_ROUTER_MANAGER, isAdmin);
    }

    function _getMessageReceiversKey(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(messageOrigin, sourceChainSelector, messageType));
    }

    function _buildChainlinkCCIPMessage(
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        address sender,
        bytes memory data
    ) internal pure returns (Client.Any2EVMMessage memory ccipMessageRecevied) {
        Client.EVMTokenAmount[] memory tokenArr = new Client.EVMTokenAmount[](0);
        ccipMessageRecevied = Client.Any2EVMMessage({
            messageId: ccipMessageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(sender),
            data: data,
            destTokenAmounts: tokenArr
        });
    }
}

contract SetSourceChainSendersTest is ReceivingRouterTests {
    function test_SetsSender() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender);

        assertEq(_router.sourceChainSenders(chainId), sender, "setSender");
    }

    function test_EmitsEvent() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectEmit(true, true, true, true);
        emit SourceChainSenderSet(chainId, sender);
        _router.setSourceChainSenders(chainId, sender);
    }

    function test_AllowsZeroAddressReceiverToBeSet() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender);
        assertEq(_router.sourceChainSenders(chainId), sender, "setSender");

        _router.setSourceChainSenders(chainId, address(0));
        assertEq(_router.sourceChainSenders(chainId), address(0), "setSender");
    }

    function test_RevertIf_ChainIsNotSupported() public {
        uint64 chainId = 12;
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, false);

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _router.setSourceChainSenders(chainId, address(1));
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        uint64 chainId = 12;
        _mockIsRouterManager(address(this), false);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.setSourceChainSenders(chainId, address(1));
    }
}

contract SetMessageReceiversTest is ReceivingRouterTests {
    function test_SavesSingleReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 1, "len");
        assertEq(newValues[0], receiver1, "receiver");
    }

    function test_SavesMultipleReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](2);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 2, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_AppendsReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receivers2 = new address[](2);
        receivers2[0] = receiver2;
        receivers2[1] = receiver3;
        _router.setMessageReceivers(sender, messageType, chainId, receivers2);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 3, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
        assertEq(newValues[2], receiver3, "receiver3");
    }

    function test_EmitsEvent() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver;

        vm.expectEmit(true, true, true, true);
        emit MessageReceiverAdded(sender, chainId, messageType, receiver);
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_ReceiverZeroAddress() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "receiverToAdd"));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGiven() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGivenInTheSameCall() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](2);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver1;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGivenInTheSameCallWithMultiple() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver1;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_SourceChainSenderNotSet() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, false);
        receivers[0] = receiver1;

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "messageOrigin"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        bytes32 messageType = 0;
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageType"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_NoRoutes() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageReceiversToSetLength"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }
}

contract RemoveMessageReceiversTest is ReceivingRouterTests {
    function test_CanRemoveOnlyReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver1;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 0, "len");
    }

    function test_CanRemoveSingleReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver2;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues.length, 2, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver3, "receiver3");
    }

    function test_EmitsEvent() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](2);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver2;

        vm.expectEmit(true, true, true, true);
        emit MessageReceiverDeleted(sender, chainId, messageType, receiver1);
        emit MessageReceiverDeleted(sender, chainId, messageType, receiver2);
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);
    }

    function test_CanRemoveFirstReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver1;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver3, "receiver3");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_CanRemoveLastReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_CanRemoveFirstAndLastReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](2);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver2, "receiver2");
    }

    function test_CanRemoveAllReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](3);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver2;
        receiversToRemove[2] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues.length, 0, "len");
    }

    function test_RevertIf_NoReceiversConfigured() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        bytes32 messageType = keccak256("message");

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _router.removeMessageReceivers(sender, messageType, 0, receiversToRemove);
    }

    function test_RevertIf_ReceiverNotFound() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver2;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = 0;
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertsIf_EmptySourceChainSelector() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertsIf_EmptyReceiver() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address zeroReceiver = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        uint64 chainId = 12;
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        receivers[0] = zeroReceiver;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "receiverToRemove"));
        _router.removeMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertIf_NoRoutesSent() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageReceiversToRemoveLength"));
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }
}

contract _ccipReceiverTests is ReceivingRouterTests {
    function test_SendToSingleMessageRecevier() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, block.timestamp, messageType, message);
        bytes32 messageHash = keccak256(data);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.expectEmit(true, true, true, true);
        emit MessageData(messageHash, block.timestamp, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver1);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);

        assertEq(_router.lastMessageSent(_getMessageReceiversKey(origin, chainId, messageType)), messageHash);
    }

    function test_SendToMultipleMessageReceivers() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, block.timestamp, messageType, message);
        bytes32 messageHash = keccak256(data);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.expectEmit(true, true, true, true);
        emit MessageData(messageHash, block.timestamp, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver1);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver2);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);

        assertEq(_router.lastMessageSent(_getMessageReceiversKey(origin, chainId, messageType)), messageHash);
    }

    function test_SendsFailureEvent_WhenFailureAtMessageReceiver() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, block.timestamp, messageType, message);
        bytes32 messageHash = keccak256(data);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        MockMessageReceiver(receiver1).setFailure(true);

        vm.expectEmit(true, true, true, true);
        emit MessageData(messageHash, block.timestamp, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageFailed(receiver1);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);

        assertEq(_router.lastMessageSent(_getMessageReceiversKey(origin, chainId, messageType)), messageHash);
    }

    function test_RevertIf_NoMessageReceiversRegistered() external {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, block.timestamp, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);

        vm.expectEmit(true, true, true, true);
        emit NoMessageReceiversRegistered(origin, messageType, chainId);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_EmitsFailureEvent_VersionMismatch() public {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        uint256 messageVersionSource = 2;
        uint256 messageVersionReceiver = CCUtils.getVersion();
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = abi.encode(
            CCUtils.Message({
                messageOrigin: origin,
                version: messageVersionSource,
                messageTimestamp: block.timestamp,
                messageType: messageType,
                message: message
            })
        );

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender);

        vm.expectEmit(true, true, true, true);
        emit MessageVersionMismatch(messageVersionSource, messageVersionReceiver);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);

        assertEq(_router.lastMessageSent(_getMessageReceiversKey(origin, chainId, messageType)), bytes32(0));
    }

    function test_EmitsFailureEvent_SourceChainSenderNotSet() public {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address senderSourceChain = makeAddr("senderSourceChain");
        address senderSetReceivingChain = makeAddr("senderSetReceivingChain");
        uint64 chainId = 12;
        bytes memory data = abi.encode("data");

        Client.Any2EVMMessage memory ccipMessage =
            _buildChainlinkCCIPMessage(messageId, chainId, senderSourceChain, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, senderSetReceivingChain);

        vm.expectEmit(true, true, true, true);
        emit InvalidSenderFromSource(chainId, senderSourceChain, senderSetReceivingChain);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_RevertIf_NotRouterCall() public {
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;
        bytes memory data = abi.encode("data");

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        vm.expectRevert(abi.encodeWithSelector(InvalidRouter.selector, address(this)));
        _router.ccipReceive(ccipMessage);
    }
}

contract ResendLastMessageTests is ReceivingRouterTests {
    function test_MultipleResends_MultipleReceivers() public {
        _mockIsRouterManager(address(this), true);

        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address receiver3 = address(new MockMessageReceiver(_systemRegistry));
        address receiver4 = address(new MockMessageReceiver(_systemRegistry));
        bytes memory messageToReceiverFirstMessage = abi.encode(1);
        bytes memory messageToReceiverSecondMessage = abi.encode(2);

        bytes memory encodedFirstMessage = CCUtils.encodeMessage(
            makeAddr("origin"), block.timestamp, keccak256("messageType1"), messageToReceiverFirstMessage
        );
        bytes memory encodedSecondMessage = CCUtils.encodeMessage(
            makeAddr("origin"), block.timestamp, keccak256("messageType2"), messageToReceiverSecondMessage
        );

        Client.Any2EVMMessage memory ccipFirstMessage =
            _buildChainlinkCCIPMessage(keccak256("ccipMessageId1"), 12, proxySender, encodedFirstMessage);
        Client.Any2EVMMessage memory ccipSecondMessage =
            _buildChainlinkCCIPMessage(keccak256("ccipMessageId2"), 12, proxySender, encodedSecondMessage);

        _mockRouterIsChainSupported(12, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receiversFirstMessage = new address[](3);
        address[] memory receiversSecondMessage = new address[](2);
        receiversFirstMessage[0] = receiver1;
        receiversFirstMessage[1] = receiver3;
        receiversFirstMessage[2] = receiver2;
        receiversSecondMessage[0] = receiver4;
        receiversSecondMessage[1] = receiver1;
        _router.setSourceChainSenders(12, proxySender);
        _router.setMessageReceivers(makeAddr("origin"), keccak256("messageType1"), 12, receiversFirstMessage);
        _router.setMessageReceivers(makeAddr("origin"), keccak256("messageType2"), 12, receiversSecondMessage);

        vm.startPrank(address(_routerClient));
        _router.ccipReceive(ccipFirstMessage);
        _router.ccipReceive(ccipSecondMessage);
        vm.stopPrank();

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](2);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: makeAddr("origin"),
            messageType: keccak256("messageType1"),
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: 12,
            message: messageToReceiverFirstMessage,
            messageReceivers: receiversFirstMessage
        });
        args[1] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: makeAddr("origin"),
            messageType: keccak256("messageType2"),
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: 12,
            message: messageToReceiverSecondMessage,
            messageReceivers: receiversSecondMessage
        });

        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver1, messageToReceiverFirstMessage);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver3, messageToReceiverFirstMessage);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver2, messageToReceiverFirstMessage);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver4, messageToReceiverSecondMessage);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver1, messageToReceiverSecondMessage);
        _router.resendLastMessage(args);
    }

    function test_SingleResend_MultipleReceivers() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address receiver3 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](3);
        receivers[0] = receiver1;
        receivers[1] = receiver3;
        receivers[2] = receiver2;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver1, messageToReceiver);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver3, messageToReceiver);
        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver2, messageToReceiver);
        _router.resendLastMessage(args);
    }

    function test_SingleResend_SingleReceiver_MultipleStorage_OnlySendsTo_RequestedReceivers() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address receiver3 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](3);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        address[] memory receiversForResend = new address[](1);
        receiversForResend[0] = receiver3;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receiversForResend
        });

        vm.recordLogs();
        _router.resendLastMessage(args);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Make sure total logs emitted on function call is what we expect.
        assertEq(logs.length, 1);
    }

    function test_SingleResend_SingleReceiver() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectEmit(true, true, true, true);
        emit MessageReceivedOnResend(receiver1, messageToReceiver);
        _router.resendLastMessage(args);
    }

    function test_RevertIf_ReceiverDoesNotExistInStorage_LastOfMultipleInStorage() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address receiver3 = address(new MockMessageReceiver(_systemRegistry));
        address receiverDNE = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](3);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        receivers[2] = receiverDNE;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(ReceivingRouter.MessageReceiverDoesNotExist.selector, receiverDNE));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_ReceiverDoesNotExistInStorage_FirstOfMultipleInStorage() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address receiver3 = address(new MockMessageReceiver(_systemRegistry));
        address receiverDNE = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](3);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        receivers[0] = receiverDNE;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(ReceivingRouter.MessageReceiverDoesNotExist.selector, receiverDNE));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_ReceiverDoesNotExistInStorage_SingleStorage() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        receivers[0] = receiver2;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(ReceivingRouter.MessageReceiverDoesNotExist.selector, receiver2));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_CurrrentReceiver_ZeroAddress_Multiple() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        address zeroAddressReceiver = address(0);
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        receivers[1] = zeroAddressReceiver;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "currentReceiver"));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_CurrrentReceiver_ZeroAddress_Single() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver = address(new MockMessageReceiver(_systemRegistry));
        address zeroAddressReceiver = address(0);
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        receivers[0] = zeroAddressReceiver;
        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "currentReceiver"));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_NoReceviersStored() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        _router.removeMessageReceivers(origin, messageType, chainId, receivers);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: messageToReceiver,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "storedReceiversLength"));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_HashMismatch() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        address proxySender = makeAddr("proxySender");
        address receiver = address(new MockMessageReceiver(_systemRegistry));
        bytes32 ccipMessageId = keccak256("ccipMessageId");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory messageToReceiver = abi.encode(1);

        bytes memory encodedMessage = CCUtils.encodeMessage(origin, block.timestamp, messageType, messageToReceiver);

        Client.Any2EVMMessage memory ccip =
            _buildChainlinkCCIPMessage(ccipMessageId, chainId, proxySender, encodedMessage);

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;
        _router.setSourceChainSenders(chainId, proxySender);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.prank(address(_routerClient));
        _router.ccipReceive(ccip);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: abi.encode(2), // Manipulate hash
            messageReceivers: receivers
        });

        bytes32 storedHash = _router.lastMessageSent(_getMessageReceiversKey(origin, chainId, messageType));
        bytes32 submittedHash = keccak256(CCUtils.encodeMessage(origin, block.timestamp, messageType, abi.encode(2)));

        vm.expectRevert(abi.encodeWithSelector(CCUtils.MismatchMessageHash.selector, storedHash, submittedHash));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_MessageReceiversNoMembers() public {
        _mockIsRouterManager(address(this), true);

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory message = abi.encode(1);
        address[] memory receivers = new address[](0);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: message,
            messageReceivers: receivers
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "resendMessageReceiversLength"));
        _router.resendLastMessage(args);
    }

    function test_RevertIf_NotRouterManager() public {
        _mockIsRouterManager(address(this), false);

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        uint64 chainId = 12;
        bytes memory message = abi.encode(1);
        address[] memory receivers = new address[](0);

        ReceivingRouter.ResendArgsReceivingChain[] memory args = new ReceivingRouter.ResendArgsReceivingChain[](1);
        args[0] = ReceivingRouter.ResendArgsReceivingChain({
            messageOrigin: origin,
            messageType: messageType,
            messageResendTimestamp: block.timestamp,
            sourceChainSelector: chainId,
            message: message,
            messageReceivers: receivers
        });

        vm.expectRevert(Errors.AccessDenied.selector);
        _router.resendLastMessage(args);
    }
}

contract MockMessageReceiver is MessageReceiverBase {
    bool public receiveFail = false;

    error Fail();

    constructor(ISystemRegistry _systemRegistry) MessageReceiverBase(_systemRegistry) { }

    function _onMessageReceive(bytes memory) internal view override {
        if (receiveFail) revert Fail();
    }

    function setFailure(bool toSet) external {
        receiveFail = toSet;
    }
}
