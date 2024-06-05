// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { EthPerTokenSender } from "src/stats/calculators/bridged/EthPerTokenSender.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { StatCalculatorRegistryMocks } from "test/unit/mocks/StatCalculatorRegistryMocks.t.sol";

// solhint-disable func-name-mixedcase,max-states-count

contract EthPerTokenSenderTests is Test, SystemRegistryMocks, AccessControllerMocks, StatCalculatorRegistryMocks {
    ISystemRegistry public systemRegistry;
    IAccessController public accessController;
    IStatsCalculatorRegistry public statCalcRegistry;
    address public messageProxy;

    EthPerTokenSender public sender;

    bytes32 public calc1Key = keccak256("calc1Key");
    address public calc1Addr = makeAddr("calc1Key");
    address public lst1 = makeAddr("lst1");

    bytes32 public calc2Key = keccak256("calc2Key");
    address public calc2Addr = makeAddr("calc2Addr");
    address public lst2 = makeAddr("lst2");

    bytes32 public calc3Key = keccak256("calc3Key");
    address public calc3Addr = makeAddr("calc3Addr");
    address public lst3 = makeAddr("lst3");

    bytes32 public calc4Key = keccak256("calc4Key");
    address public calc4Addr = makeAddr("calc4Addr");
    address public lst4 = makeAddr("lst4");

    bytes32 public calc5Key = keccak256("calc5Key");
    address public calc5Addr = makeAddr("calc5Addr");
    address public lst5 = makeAddr("lst5");

    event CalculatorsRegistered(bytes32[] calculators);
    event CalculatorsUnregistered(address[] calculators);
    event HeartbeatSet(uint256 newHeartbeat);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) StatCalculatorRegistryMocks(vm) { }

    function setUp() public {
        systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        accessController = IAccessController(makeAddr("accessController"));
        statCalcRegistry = IStatsCalculatorRegistry(makeAddr("statCalcRegistry"));
        messageProxy = makeAddr("messageProxy");

        _mockSysRegAccessController(systemRegistry, address(accessController));
        _mockSysRegStatCalcRegistry(systemRegistry, address(statCalcRegistry));
        _mockSysRegMessageProxy(systemRegistry, messageProxy);

        sender = new EthPerTokenSender(systemRegistry);

        _mockLstTokenAddress(calc1Addr, lst1);
        _mockLstTokenAddress(calc2Addr, lst2);
        _mockLstTokenAddress(calc3Addr, lst3);
        _mockLstTokenAddress(calc4Addr, lst4);
        _mockLstTokenAddress(calc5Addr, lst5);
    }

    function _mockLstTokenAddress(address calculator, address token) internal {
        vm.mockCall(calculator, abi.encodeWithSignature("lstTokenAddress()"), abi.encode(token));
    }

    function _mockCalcEthPerToken(address calculator, uint256 value) internal {
        vm.mockCall(
            calculator, abi.encodeWithSelector(LSTCalculatorBase.calculateEthPerToken.selector), abi.encode(value)
        );
    }

    function _mockMessageProxySendMessageAcceptAll() internal {
        vm.mockCall(messageProxy, abi.encodeWithSelector(IMessageProxy.sendMessage.selector), abi.encode(""));
    }

    function _mockMessageProxySendMessageRevert() internal {
        vm.mockCallRevert(messageProxy, abi.encodeWithSelector(IMessageProxy.sendMessage.selector), abi.encode(""));
    }
}

contract Constructor is EthPerTokenSenderTests {
    function test_SetUpState() public {
        assertNotEq(address(sender), address(0), "senderZero");
    }
}

contract GetCalculators is EthPerTokenSenderTests {
    function test_ReturnsAllCalculators() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](3);
        calculators[0] = calc1Key;
        calculators[1] = calc2Key;
        calculators[2] = calc3Key;
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc2Key, calc2Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc3Key, calc3Addr);

        sender.registerCalculators(calculators);

        address[] memory calcs = sender.getCalculators();
        assertEq(calcs.length, 3, "len");
        assertEq(calcs[0], calc1Addr, "addr1");
        assertEq(calcs[1], calc2Addr, "addr2");
        assertEq(calcs[2], calc3Addr, "addr3");
    }

    function test_ReturnsEmptyWhenNoneRegistered() public {
        address[] memory calcs = sender.getCalculators();
        assertEq(calcs.length, 0, "len");
    }
}

contract RegisterCalculators is EthPerTokenSenderTests {
    function test_RevertIf_NotCalledByRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        bytes32[] memory calculators = new bytes32[](1);
        calculators[0] = calc1Key;
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        sender.registerCalculators(calculators);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        sender.registerCalculators(calculators);
    }

    function test_RevertIf_NoIdsPassedIn() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        sender.registerCalculators(calculators);
    }

    function test_RevertIf_CalculatorIdNotInRegistry() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](1);
        calculators[0] = calc1Key;

        _mockStatCalcRegistryGetCalculatorRevert(statCalcRegistry, calc1Key);

        vm.expectRevert();
        sender.registerCalculators(calculators);

        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);

        sender.registerCalculators(calculators);
    }

    function test_RevertIf_CalculatorAlreadyRegistered() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](1);
        calculators[0] = calc1Key;

        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);

        sender.registerCalculators(calculators);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, calc1Addr));
        sender.registerCalculators(calculators);
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](1);
        calculators[0] = calc1Key;

        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);

        vm.expectEmit(true, true, true, true);
        emit CalculatorsRegistered(calculators);
        sender.registerCalculators(calculators);
    }

    function test_AddsSingleEntryToTheList() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](1);
        calculators[0] = calc1Key;

        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);

        sender.registerCalculators(calculators);

        assertEq(sender.getCalculators()[0], calc1Addr, "calcAddr");
    }

    function test_AddsMultipleEntriesToTheList() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](2);
        calculators[0] = calc1Key;
        calculators[1] = calc2Key;

        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc2Key, calc2Addr);

        sender.registerCalculators(calculators);

        assertEq(sender.getCalculators()[0], calc1Addr, "calcAddr1");
        assertEq(sender.getCalculators()[1], calc2Addr, "calcAddr2");
    }
}

contract UnregisterCalculators is EthPerTokenSenderTests {
    function test_RevertIf_NotCalledByRole() public {
        _setupOneAndTwo();

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        address[] memory calcToRemove = new address[](1);
        calcToRemove[0] = calc1Addr;

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        sender.unregisterCalculators(calcToRemove);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        sender.unregisterCalculators(calcToRemove);
    }

    function test_RevertIf_NoIdsPassedIn() public {
        _setupOneAndTwo();

        address[] memory calcToRemove = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        sender.unregisterCalculators(calcToRemove);
    }

    function test_RevertIf_CalculatorNotRegistered() public {
        _setupOneAndTwo();

        address[] memory calcToRemove = new address[](1);
        calcToRemove[0] = calc3Addr;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));
        sender.unregisterCalculators(calcToRemove);
    }

    function test_EmitsEvent() public {
        _setupOneAndTwo();

        address[] memory calcToRemove = new address[](2);
        calcToRemove[0] = calc1Addr;
        calcToRemove[1] = calc2Addr;

        vm.expectEmit(true, true, true, true);
        emit CalculatorsUnregistered(calcToRemove);
        sender.unregisterCalculators(calcToRemove);
    }

    function test_RemovesSingleEntryFromTheList() public {
        _setupOneAndTwo();

        address[] memory calcToRemove = new address[](1);
        calcToRemove[0] = calc1Addr;

        assertEq(sender.getCalculators().length, 2, "lenBefore");

        sender.unregisterCalculators(calcToRemove);

        assertEq(sender.getCalculators().length, 1, "lenAfter");
        assertEq(sender.getCalculators()[0], calc2Addr, "addr");
    }

    function test_RemovesMultipleEntriesFromTheList() public {
        _setupOneAndTwo();

        address[] memory calcToRemove = new address[](2);
        calcToRemove[0] = calc1Addr;
        calcToRemove[1] = calc2Addr;

        assertEq(sender.getCalculators().length, 2, "lenBefore");

        sender.unregisterCalculators(calcToRemove);

        assertEq(sender.getCalculators().length, 0, "lenAfter");
    }

    function _setupOneAndTwo() internal {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](2);
        calculators[0] = calc1Key;
        calculators[1] = calc2Key;
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc2Key, calc2Addr);

        sender.registerCalculators(calculators);
    }
}

contract ShouldSend is EthPerTokenSenderTests {
    function test_RevertIf_SkipIsGteLength() public {
        _setupThree();

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "skip"));
        sender.shouldSend(4, 4);
    }

    function test_NoZeroAddressesWhenTakeIsMoreThanLength() public {
        _setupThree();

        address[] memory shouldSend = sender.shouldSend(0, 5);
        assertEq(shouldSend.length, 3, "len");
        assertEq(shouldSend[0], calc1Addr, "calc1");
        assertEq(shouldSend[1], calc2Addr, "calc2");
        assertEq(shouldSend[2], calc3Addr, "calc3");
    }

    function test_NoZeroAddressesWhenLessUpdatesThanTake() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);
        _setupThree();
        _mockMessageProxySendMessageAcceptAll();

        address[] memory toSend = new address[](3);
        toSend[0] = calc1Addr;
        toSend[1] = calc2Addr;
        toSend[2] = calc3Addr;

        sender.execute(toSend);

        _mockCalcEthPerToken(calc2Addr, 2);

        address[] memory shouldSend = sender.shouldSend(0, 10);
        assertEq(shouldSend.length, 1, "len");
        assertNotEq(shouldSend[0], address(0), "addr");
    }

    function test_CalculatorReturnedWhenEthPerTokenChanges() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);
        _setupThree();
        _mockMessageProxySendMessageAcceptAll();

        address[] memory toSend = new address[](3);
        toSend[0] = calc1Addr;
        toSend[1] = calc2Addr;
        toSend[2] = calc3Addr;

        sender.execute(toSend);

        _mockCalcEthPerToken(calc2Addr, 2);
        _mockCalcEthPerToken(calc3Addr, 2);

        address[] memory shouldSend = sender.shouldSend(0, 10);
        assertEq(shouldSend.length, 2, "len");
        assertEq(shouldSend[0], calc2Addr, "addr1");
        assertEq(shouldSend[1], calc3Addr, "addr2");
    }

    function test_CalculatorReturnedWhenPastHeartbeat() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);
        _setupThree();
        _mockMessageProxySendMessageAcceptAll();

        address[] memory toSend = new address[](3);
        toSend[0] = calc1Addr;
        toSend[1] = calc2Addr;
        toSend[2] = calc3Addr;

        sender.execute(toSend);

        uint256 heartbeat = sender.heartbeat();

        assertEq(sender.shouldSend(0, 10).length, 0, "beforeLen");

        vm.warp(block.timestamp + heartbeat);

        assertEq(sender.shouldSend(0, type(uint256).max).length, 0, "beforeLen2");

        vm.warp(block.timestamp + 1);

        _mockCalcEthPerToken(calc2Addr, 3);

        address[] memory shouldSend = sender.shouldSend(0, 10);
        assertEq(shouldSend.length, 3, "lenAfter");
        assertEq(shouldSend[0], calc1Addr, "addr1");
        assertEq(shouldSend[1], calc2Addr, "addr2");
        assertEq(shouldSend[2], calc3Addr, "addr3");
    }

    function test_RespectsSkipAndTake() public {
        _setupThree();

        vm.warp(block.timestamp + sender.heartbeat() + 1);

        address[] memory skip = sender.shouldSend(1, 10);
        assertEq(skip.length, 2, "skipLen");
        assertEq(skip[0], calc2Addr, "skip1");
        assertEq(skip[1], calc3Addr, "skip2");

        address[] memory take = sender.shouldSend(0, 2);
        assertEq(take.length, 2, "takeLen");
        assertEq(take[0], calc1Addr, "take1");
        assertEq(take[1], calc2Addr, "take2");

        address[] memory skipTake = sender.shouldSend(1, 1);
        assertEq(skipTake.length, 1, "skipTakeLen");
        assertEq(skipTake[0], calc2Addr, "skipTake1");
    }

    function _setupThree() internal {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](3);
        calculators[0] = calc1Key;
        calculators[1] = calc2Key;
        calculators[2] = calc3Key;
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc2Key, calc2Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc3Key, calc3Addr);

        _mockCalcEthPerToken(calc1Addr, 1);
        _mockCalcEthPerToken(calc2Addr, 1);
        _mockCalcEthPerToken(calc3Addr, 1);

        sender.registerCalculators(calculators);
    }
}

contract Send is EthPerTokenSenderTests {
    function test_RevertIf_NoCalculatorsSentIn() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);

        address[] memory toSend = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        sender.execute(toSend);
    }

    function test_RevertIf_NoMessageProxyRegistered() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);

        address[] memory toSend = new address[](1);
        toSend[0] = calc1Addr;

        _mockSysRegMessageProxy(systemRegistry, address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "messageProxy"));
        sender.execute(toSend);
    }

    function test_RevertIf_CalculatorNotRegisteredWithSender() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);

        address[] memory toSend = new address[](1);
        toSend[0] = makeAddr("badAddr");

        vm.expectRevert(abi.encodeWithSelector(EthPerTokenSender.InvalidCalculator.selector, toSend[0]));
        sender.execute(toSend);
    }

    function test_RevertIf_SendNotRequired() public {
        _setupThree();
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);
        _mockMessageProxySendMessageAcceptAll();

        address[] memory toSend = new address[](2);
        toSend[0] = calc1Addr;
        toSend[1] = calc2Addr;

        uint256 timestamp = block.timestamp + 3;
        vm.warp(timestamp);

        // Set the most recent value and timestamp
        sender.execute(toSend);

        // Only number 2 has a new value and timestamps are the same
        _mockCalcEthPerToken(calc1Addr, 1);
        _mockCalcEthPerToken(calc2Addr, 2);

        vm.expectRevert(abi.encodeWithSelector(EthPerTokenSender.SendNotRequired.selector, calc1Addr));
        sender.execute(toSend);

        toSend = new address[](1);
        toSend[0] = calc2Addr;

        // Still sends if we just give it the one that has an updated value
        sender.execute(toSend);
    }

    function test_TracksMostRecentValues() public {
        _setupThree();
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);
        _mockMessageProxySendMessageAcceptAll();

        address[] memory toSend = new address[](2);
        toSend[0] = calc1Addr;
        toSend[1] = calc2Addr;

        uint256 timestamp = block.timestamp + 3;
        vm.warp(timestamp);

        sender.execute(toSend);

        (uint208 calc1EthPer, uint48 calc1Time) = sender.lastValue(calc1Addr);
        (uint208 calc2EthPer, uint48 calc2Time) = sender.lastValue(calc2Addr);
        (uint208 calc3EthPer, uint48 calc3Time) = sender.lastValue(calc3Addr);

        assertEq(calc1EthPer, 1, "calc1EthPer");
        assertEq(calc2EthPer, 1, "calc2EthPer");
        assertEq(calc3EthPer, 0, "calc3EthPer");

        assertEq(calc1Time, timestamp, "calc1Time");
        assertEq(calc2Time, timestamp, "calc2Time");
        assertEq(calc3Time, 0, "calc3Time");
    }

    function test_SendsMessageWithLatestValuesToProxy() public {
        _setupThree();
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_LST_ETH_TOKEN_EXECUTOR, true);

        uint48 timestamp = uint48(block.timestamp + 3);
        vm.warp(timestamp);

        bytes memory message = sender.encodeMessage(lst1, uint208(1), timestamp);

        _mockMessageProxySendMessageRevert();
        vm.mockCall(
            messageProxy,
            abi.encodeWithSelector(IMessageProxy.sendMessage.selector, keccak256("LST_BACKING"), message),
            abi.encode("")
        );

        address[] memory toSend = new address[](1);
        toSend[0] = calc1Addr;

        sender.execute(toSend);
    }

    function _setupThree() internal {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        bytes32[] memory calculators = new bytes32[](3);
        calculators[0] = calc1Key;
        calculators[1] = calc2Key;
        calculators[2] = calc3Key;
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc1Key, calc1Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc2Key, calc2Addr);
        _mockStatCalcRegistryGetCalculator(statCalcRegistry, calc3Key, calc3Addr);

        _mockCalcEthPerToken(calc1Addr, 1);
        _mockCalcEthPerToken(calc2Addr, 1);
        _mockCalcEthPerToken(calc3Addr, 1);

        sender.registerCalculators(calculators);
    }
}

contract SetHeartbeat is EthPerTokenSenderTests {
    function test_RevertIf_NotCalledByRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        sender.setHeartbeat(3 days);

        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);
        sender.setHeartbeat(3 days);
    }

    function test_RevertIf_ZeroValue() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "newHeartbeat"));
        sender.setHeartbeat(0);
    }

    function test_RevertIf_ExcessivelyLargeValueProvided() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "newHeartbeat"));
        sender.setHeartbeat(30 days + 1);

        sender.setHeartbeat(30 days);
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        vm.expectEmit(true, true, true, true);
        emit HeartbeatSet(3 days);
        sender.setHeartbeat(3 days);
    }

    function test_SetsNewValues() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_GENERAL_MANAGER, true);

        assertNotEq(sender.heartbeat(), 3 days, "originalValue");

        sender.setHeartbeat(3 days);

        assertEq(sender.heartbeat(), 3 days, "newValue");
    }
}
