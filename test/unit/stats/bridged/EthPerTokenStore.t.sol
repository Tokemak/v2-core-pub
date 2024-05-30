// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { EthPerTokenStore } from "src/stats/calculators/bridged/EthPerTokenStore.sol";

// solhint-disable func-name-mixedcase,contract-name-camelcase

contract EthPerTokenStoreTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry public systemRegistry;
    IAccessController public accessController;
    address public receivingRouter;

    EthPerTokenStore public store;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");

    /// =====================================================
    /// Events
    /// =====================================================

    event EthPerTokenUpdated(address indexed token, uint256 amount, uint256 timestamp);
    event MaxAgeSet(uint256 newValue);
    event TokenRegistered(address token);
    event TokenUnregistered(address token);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() public {
        systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        accessController = IAccessController(makeAddr("accessController"));
        receivingRouter = makeAddr("receivingRouter");

        _mockSysRegAccessController(systemRegistry, address(accessController));
        _mockSysRegReceivingRouter(systemRegistry, receivingRouter);

        store = new EthPerTokenStore(systemRegistry);
    }
}

contract Constructor is EthPerTokenStoreTests {
    function test_SetUpState() public {
        assertNotEq(address(store), address(0), "storeZero");
    }
}

contract SetMaxAgeSeconds is EthPerTokenStoreTests {
    function test_RevertIf_NotCalledByRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        store.setMaxAgeSeconds(100);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        store.setMaxAgeSeconds(100);
    }

    function test_RevertIf_NewAgeIsZero() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "age"));
        store.setMaxAgeSeconds(0);

        store.setMaxAgeSeconds(100);
    }

    function test_RevertIf_NewAgeIsGreaterThanTenDays() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "age"));
        store.setMaxAgeSeconds(10 days + 1);

        store.setMaxAgeSeconds(10 days);
    }

    function test_SetsNewValues() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        assertNotEq(store.maxAgeSeconds(), 100, "prevValue");

        store.setMaxAgeSeconds(100);

        assertEq(store.maxAgeSeconds(), 100, "newValue");
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectEmit(true, true, true, true);
        emit MaxAgeSet(100);
        store.setMaxAgeSeconds(100);
    }
}

contract RegisterToken is EthPerTokenStoreTests {
    function test_RevertIf_NotCalledByRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        store.registerToken(token1);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        store.registerToken(token1);
    }

    function test_RevertIf_TokenIsZero() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        store.registerToken(address(0));

        store.registerToken(token1);
    }

    function test_RevertIf_TokenIsAlreadyRegistered() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        store.registerToken(token1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, token1));
        store.registerToken(token1);
    }

    function test_RegistersToken() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        store.registerToken(token1);

        assertEq(store.registered(token1), true, "registered");
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectEmit(true, true, true, true);
        emit TokenRegistered(token1);
        store.registerToken(token1);
    }
}

contract UnregisterToken is EthPerTokenStoreTests {
    function test_RevertIf_NotCalledByRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        store.unregisterToken(token1);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        store.unregisterToken(token1);
    }

    function test_RevertIf_TokenIsNotRegistered() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));
        store.unregisterToken(token2);

        store.unregisterToken(token1);
    }

    function test_RemovesTokenFromRegistration() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        assertEq(store.registered(token1), true, "registered");

        store.unregisterToken(token1);

        assertEq(store.registered(token1), false, "unregistered");
    }

    function test_RemovesAnyTrackedDataForToken() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 10 });
        bytes memory msgBytes = abi.encode(message);

        vm.prank(receivingRouter);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);

        (uint208 ethPerToken, uint48 timestamp) = store.trackedTokens(token1);
        assertEq(ethPerToken, 3, "ethPerToken");
        assertEq(timestamp, 10, "timestamp");

        store.unregisterToken(token1);

        (uint208 newEthPerToken, uint48 newTimestamp) = store.trackedTokens(token1);
        assertEq(newEthPerToken, 0, "newEthPerToken");
        assertEq(newTimestamp, 0, "newTimestamp");
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        vm.expectEmit(true, true, true, true);
        emit TokenUnregistered(token1);
        store.unregisterToken(token1);
    }
}

contract GetEthPerToken is EthPerTokenStoreTests {
    function test_RevertIf_Stale() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 90 days });
        bytes memory msgBytes = abi.encode(message);

        vm.prank(receivingRouter);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);

        vm.expectRevert(abi.encodeWithSelector(EthPerTokenStore.ValueNotAvailable.selector, token1));
        store.getEthPerToken(token1);
    }

    function test_ReturnsLatestData() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        vm.prank(receivingRouter);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);

        (uint256 newEthPerToken, uint256 newTimestamp) = store.getEthPerToken(token1);

        assertEq(newEthPerToken, 3, "ethPer");
        assertEq(newTimestamp, 999 days, "time");
    }
}

contract _onMessageReceive is EthPerTokenStoreTests {
    function test_RevertIf_MessageIsNotSupported() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        vm.startPrank(receivingRouter);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedMessage.selector, keccak256("BAD"), msgBytes));
        store.onMessageReceive(keccak256("BAD"), msgBytes);

        vm.stopPrank();
    }

    function test_RevertIf_TokenIsNotRegistered() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token2, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        vm.startPrank(receivingRouter);

        vm.expectRevert(abi.encodeWithSelector(EthPerTokenStore.UnsupportedToken.selector, token2));
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);

        vm.stopPrank();
    }

    function test_RevertIf_TimestampIsOlderThanCurrentlyStored() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        vm.startPrank(receivingRouter);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);
        vm.stopPrank();

        message = MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days - 1 });
        msgBytes = abi.encode(message);

        vm.startPrank(receivingRouter);

        vm.expectRevert(
            abi.encodeWithSelector(EthPerTokenStore.OnlyNewerValue.selector, token1, 999 days, 999 days - 1)
        );
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);
        vm.stopPrank();
    }

    function test_EmitsEvent() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        vm.startPrank(receivingRouter);

        vm.expectEmit(true, true, true, true);
        emit EthPerTokenUpdated(token1, 3, 999 days);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);
        vm.stopPrank();
    }

    function test_SavesNewValues() public {
        vm.warp(1000 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        store.registerToken(token1);

        MessageTypes.LstBackingMessage memory message =
            MessageTypes.LstBackingMessage({ token: token1, ethPerToken: 3, timestamp: 999 days });
        bytes memory msgBytes = abi.encode(message);

        (uint208 prevEthPerToken, uint48 prevLastSetTimestamp) = store.trackedTokens(token1);

        assertNotEq(prevEthPerToken, 3, "prevEthPerToken");
        assertNotEq(prevLastSetTimestamp, 999 days, "prevLastSetTimestamp");

        vm.prank(receivingRouter);
        store.onMessageReceive(MessageTypes.LST_BACKING_MESSAGE_TYPE, msgBytes);

        (uint208 ethPerToken, uint48 lastSetTimestamp) = store.trackedTokens(token1);

        assertEq(ethPerToken, 3, "ethPerToken");
        assertEq(lastSetTimestamp, 999 days, "lastSetTimestamp");
    }
}
