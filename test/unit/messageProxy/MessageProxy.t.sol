// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { MessageProxy } from "src/messageProxy/MessageProxy.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { Errors } from "src/utils/Errors.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";
import { CrossChainMessagingUtilities as CCUtils } from "src/libs/CrossChainMessagingUtilities.sol";

// solhint-disable func-name-mixedcase,avoid-low-level-calls

contract MessageProxyTester is MessageProxy {
    constructor(ISystemRegistry _systemRegistry, IRouterClient ccipRouter) MessageProxy(_systemRegistry, ccipRouter) { }

    function buildMsg(
        address destinationChainReceiver,
        uint256 gasLimitL2,
        bytes memory message
    ) public pure returns (Client.EVM2AnyMessage memory) {
        return _ccipBuild(destinationChainReceiver, gasLimitL2, message);
    }
}

contract MessageProxyTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry internal _systemRegistry;
    IAccessController internal _accessController;
    IRouterClient internal _routerClient;

    MessageProxyTester internal _proxy;

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

    /// @notice Emitted when a message fails in try-catch.
    event MessageFailed(uint64 destChainId, bytes32 messageHash);

    /// @notice Emitted when message fails due to fee.
    event MessageFailedFee(uint64 destChainId, bytes32 messageHash, uint256 currentBalance, uint256 feeNeeded);

    /// @notice Emitted when a destination chain is not registered
    event DestinationChainNotRegisteredEvent(uint256 destChainId, bytes32 messageHash);

    /// @notice Emitted when message sent in by calculator does not exist
    event MessageZeroLength(address messageSender, bytes32 messageType);

    /// @notice Emitted when getting fee from external contracts fails.
    event GetFeeFailed(uint64 destChainSelector, bytes32 messageHash);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() external {
        _systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        _accessController = IAccessController(makeAddr("accessController"));
        _routerClient = IRouterClient(makeAddr("routerClient"));

        _mockSysRegAccessController(_systemRegistry, address(_accessController));

        _proxy = new MessageProxyTester(_systemRegistry, _routerClient);
    }

    function test_SetUpState() public {
        assertNotEq(address(_proxy), address(0), "proxy");
    }

    /// =====================================================
    /// Functions - Private Helpers
    /// =====================================================

    function _getEncodedMsgHash(
        address sender,
        uint256 nonce,
        bytes32 messageType,
        bytes memory message
    ) internal pure returns (bytes32) {
        bytes memory encodedMsg = CCUtils.encodeMessage(sender, nonce, messageType, message);
        return keccak256(encodedMsg);
    }

    function _mockRouterGetFeeAll(uint256 fee) internal {
        vm.mockCall(address(_routerClient), abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(fee));
    }

    function _mockRouterGetFee(
        address sender,
        bytes32 messageType,
        address destinationChainReceiver,
        uint64 chainId,
        uint256 gas,
        bytes memory message,
        uint256 fee
    ) internal {
        bytes memory wireMsg = CCUtils.encodeMessage(sender, _proxy.messageNonce() + 1, messageType, message);
        Client.EVM2AnyMessage memory ccipMessage = _proxy.buildMsg(destinationChainReceiver, gas, wireMsg);
        vm.mockCall(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.getFee.selector, chainId, ccipMessage),
            abi.encode(fee)
        );
    }

    function _mockRouterCcipSendAll(bytes32 resultingMessageId) internal {
        vm.mockCall(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.ccipSend.selector),
            abi.encode(resultingMessageId)
        );
    }

    function _mockRouterCcipSendRevertAll() internal {
        vm.mockCallRevert(
            address(_routerClient), abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode("")
        );
    }

    function _mockRouterIsChainSupported(uint64 chainId, bool supported) internal {
        vm.mockCall(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.isChainSupported.selector, chainId),
            abi.encode(supported)
        );
    }

    function _mockIsProxyAdmin(address user, bool isAdmin) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.MESSAGE_PROXY_MANAGER, isAdmin);
    }

    function _mockIsProxyExecutor(address user, bool isAdmin) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.MESSAGE_PROXY_EXECUTOR, isAdmin);
    }
}

contract SetDestinationChainReceiver is MessageProxyTests {
    function test_SetsReceiver() public {
        uint64 chainId = 12;
        address receiver = address(1);
        _mockIsProxyAdmin(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _proxy.setDestinationChainReceiver(chainId, receiver);

        assertEq(_proxy.destinationChainReceivers(chainId), receiver, "setReceiver");
    }

    function test_EmitsEvent() public {
        uint64 chainId = 12;
        address receiver = address(1);
        _mockIsProxyAdmin(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectEmit(true, true, true, true);
        emit ReceiverSet(chainId, receiver);
        _proxy.setDestinationChainReceiver(chainId, receiver);
    }

    function test_AllowsZeroAddressReceiverToBeSet() public {
        uint64 chainId = 12;
        address receiver = address(1);
        _mockIsProxyAdmin(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _proxy.setDestinationChainReceiver(chainId, receiver);

        assertEq(_proxy.destinationChainReceivers(chainId), receiver, "setReceiver");

        _proxy.setDestinationChainReceiver(chainId, address(0));

        assertEq(_proxy.destinationChainReceivers(chainId), address(0), "setReceiver");
    }

    function test_RevertIf_ChainIsNotSupported() public {
        uint64 chainId = 12;
        _mockIsProxyAdmin(address(this), true);
        _mockRouterIsChainSupported(chainId, false);

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _proxy.setDestinationChainReceiver(chainId, address(1));
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        uint64 chainId = 12;
        _mockIsProxyAdmin(address(this), false);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _proxy.setDestinationChainReceiver(chainId, address(1));
    }
}

contract AddMessageRoutes is MessageProxyTests {
    function test_SavesSingleRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);
        assertEq(newValues.length, 1, "len");
        assertEq(newValues[0].destinationChainSelector, chainId, "chain");
        assertEq(newValues[0].gas, 1, "gas");
    }

    function test_SavesMultipleRoutes() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](2);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);
        assertEq(newValues.length, 2, "len");
        assertEq(newValues[0].destinationChainSelector, chainId, "chain");
        assertEq(newValues[0].gas, 1, "gas");
        assertEq(newValues[1].destinationChainSelector, chainId2, "chain2");
        assertEq(newValues[1].gas, 2, "gas2");
    }

    function test_AppendsRoutes() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        MessageProxy.MessageRouteConfig[] memory routes2 = new MessageProxy.MessageRouteConfig[](2);
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes2[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes2[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });
        _proxy.addMessageRoutes(sender, messageType, routes2);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);
        assertEq(newValues.length, 3, "len");
        assertEq(newValues[0].destinationChainSelector, chainId, "chain");
        assertEq(newValues[0].gas, 1, "gas");
        assertEq(newValues[1].destinationChainSelector, chainId2, "chain2");
        assertEq(newValues[1].gas, 2, "gas2");
        assertEq(newValues[2].destinationChainSelector, chainId3, "chain3");
        assertEq(newValues[2].gas, 3, "gas3");
    }

    function test_EmitsEvent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        vm.expectEmit(true, true, true, true);
        emit MessageRouteAdded(sender, messageType, chainId);
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_DuplicateChainGiven() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_DuplicateChainGivenInTheSameCall() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](2);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_DuplicateChainGivenInTheSameCallWithMultiple() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 1 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_GivenChainIsUnsupported() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, false);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_SpecifiedGasIsZero() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 0 });

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "gas"));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "sender"));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        bytes32 messageType = 0;
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageType"));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_NoRoutes() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "routesLength"));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](0);
        _mockIsProxyAdmin(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _proxy.addMessageRoutes(sender, messageType, routes);
    }
}

contract RemovesMessageRoutes is MessageProxyTests {
    function test_CanRemoveOnlyRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainId;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues.length, 0, "len");
    }

    function test_CanRemoveSingleRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainId2;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].destinationChainSelector, chainId, "chain1");
        assertEq(newValues[0].gas, 1, "gas1");
        assertEq(newValues[1].destinationChainSelector, chainId3, "chain3");
        assertEq(newValues[1].gas, 3, "gas3");
    }

    function test_EmitsEvent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](2);
        chainsToRemove[0] = chainId;
        chainsToRemove[1] = chainId2;

        vm.expectEmit(true, true, true, true);
        emit MessageRouteDeleted(sender, messageType, chainId);
        emit MessageRouteDeleted(sender, messageType, chainId2);
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);
    }

    function test_CanRemoveFirstRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainId;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].destinationChainSelector, chainId3, "chain3");
        assertEq(newValues[0].gas, 3, "gas3");
        assertEq(newValues[1].destinationChainSelector, chainId2, "chain2");
        assertEq(newValues[1].gas, 2, "gas2");
    }

    function test_CanRemoveLastRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainId3;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].destinationChainSelector, chainId, "chain");
        assertEq(newValues[0].gas, 1, "gas");
        assertEq(newValues[1].destinationChainSelector, chainId2, "chain2");
        assertEq(newValues[1].gas, 2, "gas2");
    }

    function test_CanRemoveFirstAndLastRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](2);
        chainsToRemove[0] = chainId;
        chainsToRemove[1] = chainId3;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].destinationChainSelector, chainId2, "chain2");
        assertEq(newValues[0].gas, 2, "gas2");
    }

    function test_CanRemoveAllRoutes() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](3);
        chainsToRemove[0] = chainId;
        chainsToRemove[1] = chainId3;
        chainsToRemove[2] = chainId2;
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues.length, 0, "len");
    }

    function test_RevertIf_NoRoutesConfigured() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");

        uint64[] memory chainsToRemove = new uint64[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);
    }

    function test_RevertIf_RouteNotFound() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainId + 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _proxy.removeMessageRoutes(sender, messageType, chainsToRemove);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        bytes32 messageType = keccak256("message");
        uint64[] memory routes = new uint64[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "sender"));
        _proxy.removeMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        bytes32 messageType = 0;
        uint64[] memory routes = new uint64[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageType"));
        _proxy.removeMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        uint64[] memory routes = new uint64[](0);
        _mockIsProxyAdmin(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _proxy.removeMessageRoutes(sender, messageType, routes);
    }

    function test_RevertIf_NoRoutesSent() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        uint64[] memory routes = new uint64[](0);
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "chainLength"));
        _proxy.removeMessageRoutes(sender, messageType, routes);
    }
}

contract SetGasForRoute is MessageProxyTests {
    function test_EmitsEvent() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        vm.expectEmit(true, true, true, true);
        emit GasUpdated(sender, messageType, chainId2, 4);
        _proxy.setGasForRoute(sender, messageType, chainId2, 4);
    }

    function test_UpdatesGasOnSpecifiedChain() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        _proxy.setGasForRoute(sender, messageType, chainId2, 4);
        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].gas, 1, "gas1");
        assertEq(newValues[1].gas, 4, "gasNew");
        assertEq(newValues[2].gas, 3, "gasNew");
    }

    function test_UpdatesGasOnSpecifiedChainWhenLast() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        _proxy.setGasForRoute(sender, messageType, chainId3, 4);
        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].gas, 1, "gas1");
        assertEq(newValues[1].gas, 2, "gas2");
        assertEq(newValues[2].gas, 4, "gasNew");
    }

    function test_UpdatesGasOnSpecifiedChainWhenFirst() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        _proxy.setGasForRoute(sender, messageType, chainId, 4);
        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);

        assertEq(newValues[0].gas, 4, "gasNew");
        assertEq(newValues[1].gas, 2, "gas2");
        assertEq(newValues[2].gas, 3, "gas3");
    }

    function test_RevertIf_ChainDoesNotExist() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _proxy.setGasForRoute(sender, messageType, 9, 4);
    }

    function test_RevertIf_ChainDoesNotExistZero() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _proxy.setGasForRoute(sender, messageType, 0, 4);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        bytes32 messageType = keccak256("message");
        uint64 chainId = 12;
        uint192 gas = 1;
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "sender"));
        _proxy.setGasForRoute(sender, messageType, chainId, gas);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        bytes32 messageType = 0;
        uint64 chainId = 12;
        uint192 gas = 1;
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageType"));
        _proxy.setGasForRoute(sender, messageType, chainId, gas);
    }

    function test_RevertIf_EmptyGas() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        uint64 chainId = 12;
        uint192 gas = 0;
        _mockIsProxyAdmin(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "gas"));
        _proxy.setGasForRoute(sender, messageType, chainId, gas);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        uint64 chainId = 12;
        uint192 gas = 1;
        _mockIsProxyAdmin(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _proxy.setGasForRoute(sender, messageType, chainId, gas);
    }
}

contract GetMessageRoutes is MessageProxyTests {
    function test_ReturnsRoutes() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        _mockIsProxyAdmin(address(this), true);
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](3);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        uint64 chainId3 = 14;
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _mockRouterIsChainSupported(chainId3, true);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 2 });
        routes[2] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId3, gas: 3 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);
        assertEq(newValues[0].destinationChainSelector, chainId, "val1");
        assertEq(newValues[0].gas, 1, "gas1");
        assertEq(newValues[1].destinationChainSelector, chainId2, "val2");
        assertEq(newValues[1].gas, 2, "gas2");
        assertEq(newValues[2].destinationChainSelector, chainId3, "val3");
        assertEq(newValues[2].gas, 3, "gas3");
    }

    function test_ReturnsEmptyWhenNoRoutesRegistered() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        MessageProxy.MessageRouteConfig[] memory newValues = _proxy.getMessageRoutes(sender, messageType);
        assertEq(newValues.length, 0, "len");
    }
}

contract GetFee is MessageProxyTests {
    function test_RevertsWhen_DestChainSelectorHasNoReceiver() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");

        // Set message route but no dest chain receiver.
        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ZeroAddress.selector, "destinationChainReceivers[destChainSelector]")
        );
        _proxy.getFee(sender, messageType, message);
    }

    function test_ReturnsEmptiesWhenNoRoutes() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");

        (uint64[] memory chains, uint256[] memory fees) = _proxy.getFee(sender, messageType, message);
        assertEq(chains.length, 0, "chainLen");
        assertEq(fees.length, 0, "gasLen");
    }

    function test_ReturnsFeeForSingleRoute() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);

        uint64 chainId = 12;
        address chainReceiver = makeAddr("receiver12");
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint256 fee = 433;
        _mockRouterGetFee(sender, messageType, chainReceiver, chainId, 1, message, fee);

        (uint64[] memory chains, uint256[] memory fees) = _proxy.getFee(sender, messageType, message);
        assertEq(chains.length, 1, "chainLen");
        assertEq(fees.length, 1, "gasLen");
        assertEq(chains[0], chainId, "chain");
        assertEq(fees[0], fee, "fee");
    }

    function test_ReturnsFeeForMultipleRoutes() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](2);

        uint64 chainId = 12;
        uint64 chainId2 = 13;
        address chainReceiver = makeAddr("receiver12");
        address chainReceiver2 = makeAddr("receiver13");
        _mockRouterIsChainSupported(chainId, true);
        _mockRouterIsChainSupported(chainId2, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        _proxy.setDestinationChainReceiver(chainId2, chainReceiver2);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId2, gas: 1 });

        _proxy.addMessageRoutes(sender, messageType, routes);

        uint256 fee = 433;
        uint256 fee2 = 4332;
        _mockRouterGetFee(sender, messageType, chainReceiver, chainId, 1, message, fee);
        _mockRouterGetFee(sender, messageType, chainReceiver2, chainId2, 1, message, fee2);

        (uint64[] memory chains, uint256[] memory fees) = _proxy.getFee(sender, messageType, message);
        assertEq(chains.length, 2, "chainLen");
        assertEq(fees.length, 2, "gasLen");
        assertEq(chains[0], chainId, "chain");
        assertEq(fees[0], fee, "fee");
        assertEq(chains[1], chainId2, "chain2");
        assertEq(fees[1], fee2, "fee2");
    }
}

contract Receive is MessageProxyTests {
    function test_CanReceiveEth() public {
        address user = makeAddr("user");
        deal(user, 1000e18);

        assertEq(payable(_proxy).balance, 0, "initialBalance");

        vm.prank(user);
        (bool success,) = payable(_proxy).call{ value: 100e18 }("");

        assertEq(success, true, "success");
        assertEq(payable(_proxy).balance, 100e18, "updatedBalance");
    }
}

contract SendMessage is MessageProxyTests {
    function test_DoesNotRevertWhenNoRoutes() public {
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        uint256 messageNonceBefore = _proxy.messageNonce();

        _proxy.sendMessage(messageType, message);
        assertEq(_proxy.messageNonce(), messageNonceBefore);
    }

    function test_SavesLastMessageSent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 1e9);

        assertNotEq(_proxy.lastMessageSent(sender, messageType), messageHash, "startingHash");

        vm.startPrank(sender);
        _proxy.sendMessage(messageType, message);
        vm.stopPrank();

        assertEq(_proxy.lastMessageSent(sender, messageType), messageHash, "endingHash");
        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsMessageDataEvent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(keccak256("msgId"));

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageData(messageHash, messageNonceBefore + 1, sender, messageType, message);
        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsMissingReceiverEvent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 1e9);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageData(messageHash, messageNonceBefore + 1, sender, messageType, message);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit DestinationChainNotRegisteredEvent(chainId, messageHash);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsGetFeeFailedEvent() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");
        address chainReceiver = makeAddr("chainReceiver12");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        // Mock getFee revert
        // solhint-disable-next-line  max-line-length
        vm.mockCallRevert(address(_routerClient), abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(""));

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);
        uint256 dealAmount = 1e9;
        deal(address(_proxy), dealAmount);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true);
        emit GetFeeFailed(chainId, messageHash);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsMessageSentEventForDestinationChain() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 1e9);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageData(messageHash, messageNonceBefore + 1, sender, messageType, message);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageSent(chainId, messageHash, ccipMsgId);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsMessageFailedEventForDestinationChain() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendRevertAll();

        // Make sure we can pass the fee checks
        deal(address(_proxy), 1e9);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageData(messageHash, messageNonceBefore + 1, sender, messageType, message);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageFailed(chainId, messageHash);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    function test_EmitsFeeFailedEventForDestinationChain() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes32 messageHash = _getEncodedMsgHash(sender, messageNonceBefore + 1, messageType, message);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 1e9 - 1);

        vm.startPrank(sender);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageData(messageHash, messageNonceBefore + 1, sender, messageType, message);

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageFailedFee(chainId, messageHash, 1e9 - 1, 1e9);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }

    // Testing for Toke-29.  Ref: https://github.com/Tokemak/v2-core/issues/720
    function test_OperatesProperlyWhenSinglegetFeeCallFails() public {
        _mockIsProxyAdmin(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](2);

        address chainReceiver12 = makeAddr("chainReceiver12");
        address chainReceiver14 = makeAddr("chainReceiver14");

        uint64 chainId12 = 12;
        uint64 chainId14 = 14;

        _mockRouterIsChainSupported(chainId12, true);
        _mockRouterIsChainSupported(chainId14, true);

        _proxy.setDestinationChainReceiver(chainId12, chainReceiver12);
        _proxy.setDestinationChainReceiver(chainId14, chainReceiver14);

        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId12, gas: 1 });
        routes[1] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId14, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 messageNonceBefore = _proxy.messageNonce();
        bytes memory encodedMsg = CCUtils.encodeMessage(sender, messageNonceBefore + 1, messageType, message);
        bytes32 messageHash = keccak256(encodedMsg);

        // Two messages
        deal(address(_proxy), 1e9 * 2);

        // Building ccip message, need explicit calldata for reverting single getFee out of multiple calls
        Client.EVM2AnyMessage memory ccipMessage = _proxy.buildMsg(chainReceiver12, 1, encodedMsg);

        // Actual revert message does not matter here, just want it to revert
        vm.mockCallRevert(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.getFee.selector, chainId12, ccipMessage),
            "REVERT"
        );

        vm.startPrank(sender);

        // For `expectEmit`, emitted events must always be in order.  `GetFeeFailed` first, `MessageSent` second
        // Vaidates both order to ensure that continue is being tested, and that we are getting one send and one fail
        vm.expectEmit(true, true, true, true);
        emit GetFeeFailed(chainId12, messageHash);

        vm.expectEmit(true, true, true, true);
        emit MessageSent(chainId14, messageHash, ccipMsgId);

        _proxy.sendMessage(messageType, message);

        vm.stopPrank();

        assertEq(_proxy.messageNonce(), messageNonceBefore + 1);
    }
}

contract ResendLastMessage is MessageProxyTests {
    function test_EmitsMessageSentEventForDestinationChain() public {
        _mockIsProxyAdmin(address(this), true);
        _mockIsProxyExecutor(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        uint256 nonce = _proxy.messageNonce() + 1;
        bytes32 messageHash = _getEncodedMsgHash(sender, nonce, messageType, message);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 100e9);

        vm.startPrank(sender);
        _proxy.sendMessage(messageType, message);
        vm.stopPrank();

        // Give ourselves some ETH to work with
        deal(address(this), 100e9);

        bytes32 ccipMsgId2 = keccak256("msgId2");
        _mockRouterCcipSendAll(ccipMsgId2);

        MessageProxy.ResendArgsSendingChain[] memory args = new MessageProxy.ResendArgsSendingChain[](1);
        args[0] = MessageProxy.ResendArgsSendingChain({
            msgSender: sender,
            messageType: messageType,
            messageNonce: nonce,
            message: message,
            configs: routes
        });

        vm.expectEmit(true, true, true, true, address(_proxy));
        emit MessageSent(chainId, messageHash, ccipMsgId2);

        _proxy.resendLastMessage{ value: 1e9 }(args);
    }

    function test_RevertIf_SenderDoesntPayForCCIPFees() public {
        _mockIsProxyAdmin(address(this), true);
        _mockIsProxyExecutor(address(this), true);

        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        bytes memory message = abi.encode("message");

        MessageProxy.MessageRouteConfig[] memory routes = new MessageProxy.MessageRouteConfig[](1);
        address chainReceiver = makeAddr("chainReceiver12");
        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _proxy.setDestinationChainReceiver(chainId, chainReceiver);
        routes[0] = MessageProxy.MessageRouteConfig({ destinationChainSelector: chainId, gas: 1 });
        _proxy.addMessageRoutes(sender, messageType, routes);

        bytes32 ccipMsgId = keccak256("msgId");
        _mockRouterGetFeeAll(1e9);
        _mockRouterCcipSendAll(ccipMsgId);

        // Make sure we can pass the fee checks
        deal(address(_proxy), 100e9);

        vm.startPrank(sender);
        _proxy.sendMessage(messageType, message);
        vm.stopPrank();

        // Give ourselves some ETH to work with
        deal(address(this), 100e9);

        bytes32 ccipMsgId2 = keccak256("msgId2");
        _mockRouterCcipSendAll(ccipMsgId2);

        MessageProxy.ResendArgsSendingChain[] memory args = new MessageProxy.ResendArgsSendingChain[](1);
        args[0] = MessageProxy.ResendArgsSendingChain({
            msgSender: sender,
            messageType: messageType,
            messageNonce: _proxy.messageNonce(),
            message: message,
            configs: routes
        });

        vm.expectRevert(abi.encodeWithSelector(MessageProxy.NotEnoughFee.selector, 1e9 - 1, 1e9));
        _proxy.resendLastMessage{ value: 1e9 - 1 }(args);

        assertTrue(payable(_proxy).balance > 1e9, "contractHasBalance");
    }
}
