// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseTest } from "test/BaseTest.t.sol";
import { CCIP_ROUTER_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";

import { MessageProxy } from "src/messageProxy/MessageProxy.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { IRouter, Client } from "src/interfaces/external/chainlink/IRouter.sol";

// solhint-disable const-name-snakecase,max-line-length,func-name-mixedcase

/// @dev These tests test interactions with Ethereum ccip router, does not test cross chain functionality.
contract MessageProxyIntegTests is BaseTest {
    /// =====================================================
    /// State - constant
    /// =====================================================

    bytes32 public constant messageType1 = keccak256("messageType1");
    bytes32 public constant messageType2 = keccak256("messageType2");

    // Chainlink destination info - https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet#overview
    uint64 public constant baseDestSelector = 15_971_525_489_660_198_786;
    uint64 public constant optimismDestSelector = 3_734_403_246_176_062_136;

    // Generic gas limit for these tests, not actually going to L2.
    uint256 public constant gasLimit = 100_000;

    // Eth to transfer to message proxy.
    uint256 public constant ethTransferValue = 1e18;

    /// =====================================================
    /// State - immutable
    /// =====================================================

    // Don't have real receiver contract addresses
    address public immutable destChainReceiverBase = makeAddr("destChainReceiverBase");
    address public immutable destChainReceiverOptimism = makeAddr("destChainReceiverOptimism");

    /// =====================================================
    /// State - Set during test setup
    /// =====================================================

    MessageProxy public messageProxy;

    bytes public message1;
    bytes public message2;

    address public baseOnRamp;
    address public optimismOnRamp;

    /// =====================================================
    /// Events
    /// =====================================================

    // Chainlink event, emitted from router interaction.  See struct definition below for more information.
    event CCIPSendRequested(EVM2EVMMessage message);

    event MessageData(
        bytes32 indexed messageHash, uint256 messageTimestamp, address sender, bytes32 messageType, bytes message
    );

    event MessageSent(uint64 destChainSelector, bytes32 messageHash, bytes32 ccipMessageId);

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @notice Taken from Chainlink Internal.sol contract, used in CCIPSendRequested event.
    /// @notice Link here:
    /// https://github.com/smartcontractkit/ccip/blob/d26cee7bbe0d67b771caed9c0d65b10adfb3035a/contracts/src/v0.8/ccip/libraries/Internal.sol#L67
    /// @notice The cross chain message that gets committed to EVM chains.
    struct EVM2EVMMessage {
        uint64 sourceChainSelector; // ───────────╮ the chain selector of the source chain, note: not chainId
        address sender; // ───────────────────────╯ sender address on the source chain
        address receiver; // ─────────────────────╮ receiver address on the destination chain
        uint64 sequenceNumber; // ────────────────╯ sequence number, not unique across lanes
        uint256 gasLimit; //                        user supplied maximum gas amount available for dest chain execution
        bool strict; // ──────────────────────────╮ DEPRECATED
        uint64 nonce; //                          │ nonce for this lane for this sender, not unique across senders/lanes
        address feeToken; // ─────────────────────╯ fee token
        uint256 feeTokenAmount; //                  fee token amount
        bytes data; //                              arbitrary data payload supplied by the message sender
        Client.EVMTokenAmount[] tokenAmounts; //    array of tokens and amounts to transfer
        bytes[] sourceTokenData; //                 array of token data, one per token
        bytes32 messageId; //                       a hash of the message data
    }

    function setUp() public virtual override {
        forkBlock = 19_761_919;
        super.setUp();

        // Set up message proxy
        messageProxy = new MessageProxy(systemRegistry, IRouterClient(CCIP_ROUTER_MAINNET));

        // Role setup
        accessController.setupRole(Roles.MESSAGE_PROXY_ADMIN, address(this));

        // Set dest chain info
        messageProxy.setDestinationChainReceiver(baseDestSelector, destChainReceiverBase);
        messageProxy.setDestinationChainReceiver(optimismDestSelector, destChainReceiverOptimism);

        // Set up messages.  Arbitrary info, don't have message definitions yet.
        message1 = abi.encode(makeAddr("address"), 1e18);
        message2 = abi.encode(keccak256("string"), makeAddr("address"), 100_111_222, 43);

        // Get on Chainlink on ramps.  Addresses receive weth on `ccipSend` call, used to check funds go right place
        baseOnRamp = IRouter(CCIP_ROUTER_MAINNET).getOnRamp(baseDestSelector);
        optimismOnRamp = IRouter(CCIP_ROUTER_MAINNET).getOnRamp(optimismDestSelector);

        // Send funds for payment to message proxy
        payable(messageProxy).transfer(1e18);

        // Set up base route for messageType1
        _addMessageRoute(baseDestSelector, messageType1);
    }

    /// @dev Add single config
    function _addMessageRoute(uint64 _destinationChainSelector, bytes32 _messageType) internal {
        MessageProxy.MessageRouteConfig[] memory config = new MessageProxy.MessageRouteConfig[](1);
        config[0] = MessageProxy.MessageRouteConfig({
            destinationChainSelector: _destinationChainSelector,
            gas: uint192(gasLimit)
        });

        messageProxy.addMessageRoutes(address(this), _messageType, config);
    }

    // Add up and return total fees
    function _getTotalFee(uint256[] memory feesArr) internal pure returns (uint256 totalFee) {
        for (uint256 i = 0; i < feesArr.length; ++i) {
            totalFee += feesArr[i];
        }
    }
}

contract SendMessageIntegTests is MessageProxyIntegTests {
    function setUp() public override {
        super.setUp();
    }

    function test_sendMessage_SingleDestination() public {
        uint256 timestamp = block.timestamp;
        bytes memory messageBytes = messageProxy.encodeMessage(address(this), 1, timestamp, messageType1, message1);
        bytes32 messageHash = keccak256(messageBytes);

        // get fees
        (, uint256[] memory fees) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 expectedFee = _getTotalFee(fees);

        // Router wraps Eth to Weth, sends to onRamp contract.
        uint256 baseOnRampWethBalanceBefore = weth.balanceOf(baseOnRamp);

        vm.expectEmit(true, true, true, true);
        emit MessageData(messageHash, timestamp, address(this), messageType1, message1);

        // Just checking signature, some parts of struct filled with arbitrary info.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(baseDestSelector, messageHash, keccak256("placeholder"));

        messageProxy.sendMessage(messageType1, message1);

        // Router swaps to weth, send to onRamp contract
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampWethBalanceBefore + expectedFee);
        assertEq(address(messageProxy).balance, ethTransferValue - expectedFee);
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHash);
    }

    function test_sendMessage_MultipleDestinations() public {
        // Add optimism destination for messageType1 config.  Will be added to second array slot in storage.
        _addMessageRoute(optimismDestSelector, messageType1);

        uint256 timestamp = block.timestamp;
        bytes memory messageBytes = messageProxy.encodeMessage(address(this), 1, timestamp, messageType1, message1);
        bytes32 messageHash = keccak256(messageBytes);

        // Get expected fees
        (, uint256[] memory gas) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 expectedTotalFee = _getTotalFee(gas);
        uint256 baseExpectedFee = gas[0];
        uint256 optimismExpectedFee = gas[1];

        // Router wraps Eth to Weth, sends to onRamp contract.
        uint256 baseOnRampWethBalanceBefore = weth.balanceOf(baseOnRamp);
        uint256 optimismOnRampWethBalanceBefore = weth.balanceOf(optimismOnRamp);

        // One emitted per sendMessage call.
        vm.expectEmit(true, true, true, true);
        emit MessageData(messageHash, timestamp, address(this), messageType1, message1);

        //
        // First destination - Base
        //

        // Just checking signature, some parts of struct filled with arbitrary info.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverOptimism,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(optimismDestSelector, messageHash, keccak256("placeholder"));

        //
        // Second destination - optimism.
        //
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId, just check for signature
        vm.expectEmit(true, true, true, false);
        emit MessageSent(baseDestSelector, messageHash, keccak256("placeholder"));

        messageProxy.sendMessage(messageType1, message1);

        // Router swaps to weth, send to onRamp contract
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampWethBalanceBefore + baseExpectedFee, "baseOnRamp");
        assertEq(
            weth.balanceOf(optimismOnRamp), optimismOnRampWethBalanceBefore + optimismExpectedFee, "optimismOnRamp"
        );
        assertEq(address(messageProxy).balance, ethTransferValue - expectedTotalFee, "totalFee");
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHash, "lastMessageSent");
    }
}

contract ResendLastMessageIntegTests is MessageProxyIntegTests {
    uint256 public message1Type1SendTimestamp;
    uint256 public messageProxyStoredBalance;

    function setUp() public virtual override {
        super.setUp();

        // Snapshot timestamp for original message send.
        message1Type1SendTimestamp = block.timestamp;

        // Set one message in `lastMessage` via `sendMessage`.  Not actually checked for failure so this works.
        // Will be messageType1 and message1 sent to base, only route configured at this point.
        messageProxy.sendMessage(messageType1, message1);

        // Snapshot contract balance after message send, will have burned some Eth.
        messageProxyStoredBalance = address(messageProxy).balance;
    }

    // Revert when last message hash does not equal message sent in.
    function test_resendLastMessage_RevertWhen_MessageHashMismatch() public {
        // Recreate hash on our own, make sure that we have correct hash stored.
        bytes32 expectedStoredMessageHash =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message1));
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), expectedStoredMessageHash);

        // Build incorrect message hash for error validation.  Change message.
        bytes32 messageHashBuiltOnFunctionCall =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message2));

        // Build retryArgs array with same data as above
        // Configs being zero length doesn't matter here, targeted revert above where configs touched.
        MessageProxy.MessageRouteConfig[] memory configs = new MessageProxy.MessageRouteConfig[](0);
        MessageProxy.RetryArgs[] memory retryArgs = new MessageProxy.RetryArgs[](1);
        retryArgs[0] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType1,
            messageRetryTimestamp: message1Type1SendTimestamp,
            message: message2,
            configs: configs
        });

        // Call resend incorrect params causing an invalid message hash to be created, will fail.
        vm.expectRevert(
            abi.encodeWithSelector(
                MessageProxy.MismatchMessageHash.selector, expectedStoredMessageHash, messageHashBuiltOnFunctionCall
            )
        );
        messageProxy.resendLastMessage(retryArgs);
    }

    // Test single `RetryArgs` struct with single config.
    function test_resendLastMessage_SingleRetryArgsStruct_SingleConfig() public {
        // Get message hash for below checks
        bytes32 messageHash =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message1));

        // Build retryArgs and configs
        MessageProxy.MessageRouteConfig[] memory configs = new MessageProxy.MessageRouteConfig[](1);
        configs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: baseDestSelector, gas: uint192(gasLimit) });
        MessageProxy.RetryArgs[] memory retryArgs = new MessageProxy.RetryArgs[](1);
        retryArgs[0] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType1,
            messageRetryTimestamp: message1Type1SendTimestamp,
            message: message1,
            configs: configs
        });

        // Snapshot onRamp weth balance
        uint256 baseOnRampBalanceBefore = weth.balanceOf(baseOnRamp);

        // Get expected fees.  One destination, can use for both total and dest checks.
        (, uint256[] memory gas) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 expectedTotalFee = gas[0];

        //
        // Event checks
        //

        // Just checking for event signature.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(baseDestSelector, messageHash, keccak256("placeholder"));

        messageProxy.resendLastMessage{ value: expectedTotalFee }(retryArgs);

        // Checks for messageProxy balance, onRamp balance, stored lastMessageSent not being deleted
        assertEq(address(messageProxy).balance, messageProxyStoredBalance, "messageProxyBalance");
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampBalanceBefore + expectedTotalFee, "baseOnRampBalance");
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHash, "messageHash");
    }

    // Test single `RetryArgs` struct with multiple configs.
    function test_resendLastMessage_SingleRetryArgsStruct_MultipleConfigs() public {
        _addMessageRoute(optimismDestSelector, messageType1);

        // Get message hash for below checks
        bytes32 messageHash =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message1));

        // Build retryArgs and configs
        MessageProxy.MessageRouteConfig[] memory configs = new MessageProxy.MessageRouteConfig[](2);
        configs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: baseDestSelector, gas: uint192(gasLimit) });
        configs[1] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: optimismDestSelector, gas: uint192(gasLimit) });
        MessageProxy.RetryArgs[] memory retryArgs = new MessageProxy.RetryArgs[](1);
        retryArgs[0] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType1,
            messageRetryTimestamp: message1Type1SendTimestamp,
            message: message1,
            configs: configs
        });

        // Snapshot onRamp weth balances
        uint256 baseOnRampBalanceBefore = weth.balanceOf(baseOnRamp);
        uint256 optimismOnRampBalanceBefore = weth.balanceOf(optimismOnRamp);

        // Get expected fees.
        (, uint256[] memory gas) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 expectedTotalFee = _getTotalFee(gas);
        uint256 baseExpectedFee = gas[0];
        uint256 optimismExpectedFee = gas[1];

        //
        // Event checks
        //

        // Just checking for event signature.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(baseDestSelector, messageHash, keccak256("placeholder"));

        // Just checking for event signature.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverOptimism,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(optimismDestSelector, messageHash, keccak256("placeholder"));

        messageProxy.resendLastMessage{ value: expectedTotalFee }(retryArgs);

        assertEq(address(messageProxy).balance, messageProxyStoredBalance, "messageProxyBalance");
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampBalanceBefore + baseExpectedFee, "baseOnRampBalance");
        assertEq(
            weth.balanceOf(optimismOnRamp), optimismOnRampBalanceBefore + optimismExpectedFee, "optimismOnRampBalance"
        );
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHash, "messageHash");
    }

    // Test single `RetryArgs` struct with multiple configs registered but only one used.
    function test_resendLastMessage_SingleRetryArgsStruct_MultipleConfigs_WithOneNotUsed() public {
        _addMessageRoute(optimismDestSelector, messageType1);

        // Get message hash for below checks
        bytes32 messageHash =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message1));

        // Build retryArgs and configs.  Only optimism for this one.
        MessageProxy.MessageRouteConfig[] memory configs = new MessageProxy.MessageRouteConfig[](1);
        configs[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: optimismDestSelector, gas: uint192(gasLimit) });
        MessageProxy.RetryArgs[] memory retryArgs = new MessageProxy.RetryArgs[](1);
        retryArgs[0] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType1,
            messageRetryTimestamp: message1Type1SendTimestamp,
            message: message1,
            configs: configs
        });

        // Get all registered routes for sender and message type, ensure length > 1
        MessageProxy.MessageRouteConfig[] memory configsForLengthCheck =
            messageProxy.getMessageRoutes(address(this), messageType1);
        assertGt(configsForLengthCheck.length, 1);

        // Snapshot onRamp weth balances
        uint256 baseOnRampBalanceBefore = weth.balanceOf(baseOnRamp);
        uint256 optimismOnRampBalanceBefore = weth.balanceOf(optimismOnRamp);

        // Get expected fees. Optimism fee only for this one
        (, uint256[] memory gas) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 expectedTotalFee = gas[1];

        //
        // Event checks
        //

        // Just checking for event signature.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverOptimism,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(optimismDestSelector, messageHash, keccak256("placeholder"));

        messageProxy.resendLastMessage{ value: expectedTotalFee }(retryArgs);

        assertEq(address(messageProxy).balance, messageProxyStoredBalance, "messageProxyBalance");
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampBalanceBefore, "baseOnRampBalance");
        assertEq(
            weth.balanceOf(optimismOnRamp), optimismOnRampBalanceBefore + expectedTotalFee, "optimismOnRampBalance"
        );
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHash, "messageHash");
    }

    // Test multiple `RetryArgs` structs, one with multiple configs, other with single config.
    function test_resendLastMessage_MultipleRetryArgsStructs_MultipleConfigs() public {
        _addMessageRoute(optimismDestSelector, messageType1);
        // Add a second route, same sender different message type.
        _addMessageRoute(baseDestSelector, messageType2);

        // Send message2 in order to set lastMessageSet hash
        uint256 message2Type2SendTimestamp = block.timestamp;
        messageProxy.sendMessage(messageType2, message2);

        // Snapshot balance after regular message send, takes from contract balance
        messageProxyStoredBalance = address(messageProxy).balance;

        // Get message hash for below checks
        bytes32 messageHashType1 =
            keccak256(messageProxy.encodeMessage(address(this), 1, message1Type1SendTimestamp, messageType1, message1));
        bytes32 messageHashType2 =
            keccak256(messageProxy.encodeMessage(address(this), 1, message2Type2SendTimestamp, messageType2, message2));

        //
        // Build retryArgs and configs
        //

        // Configs for message type 1, will be optimism and base
        MessageProxy.MessageRouteConfig[] memory configsMessageType1 = new MessageProxy.MessageRouteConfig[](2);
        configsMessageType1[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: baseDestSelector, gas: uint192(gasLimit) });
        configsMessageType1[1] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: optimismDestSelector, gas: uint192(gasLimit) });

        // Configs for message type 2, just base
        MessageProxy.MessageRouteConfig[] memory configsMessageType2 = new MessageProxy.MessageRouteConfig[](1);
        configsMessageType2[0] =
            MessageProxy.MessageRouteConfig({ destinationChainSelector: baseDestSelector, gas: uint192(gasLimit) });

        // Retry args array, two memebers for two different message sender and type combinations
        MessageProxy.RetryArgs[] memory retryArgs = new MessageProxy.RetryArgs[](2);
        retryArgs[0] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType1,
            messageRetryTimestamp: message1Type1SendTimestamp,
            message: message1,
            configs: configsMessageType1
        });
        retryArgs[1] = MessageProxy.RetryArgs({
            msgSender: address(this),
            messageType: messageType2,
            messageRetryTimestamp: message2Type2SendTimestamp,
            message: message2,
            configs: configsMessageType2
        });

        // Snapshot onRamp weth balances
        uint256 baseOnRampBalanceBefore = weth.balanceOf(baseOnRamp);
        uint256 optimismOnRampBalanceBefore = weth.balanceOf(optimismOnRamp);

        //
        // Get expected fees.
        //

        // For message type 1, Optimism destination only registered here.
        (, uint256[] memory gasMessageType1) = messageProxy.getFee(address(this), messageType1, message1);
        uint256 optimismExpectedFee = gasMessageType1[1];

        (, uint256[] memory gasMessageType2) = messageProxy.getFee(address(this), messageType2, message2);
        // Array of message type 1 gas + base dest fee from messageType1
        uint256 expectedTotalFee = _getTotalFee(gasMessageType1) + gasMessageType2[0];
        // Base expected fees for both message types.
        uint256 baseTotalExpectedFee = gasMessageType1[0] + gasMessageType2[0];

        //
        // Event checks - Three of each, per destination
        //

        // First round, messageType1, base destination
        // Just checking for event signature.
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(baseDestSelector, messageHashType1, keccak256("placeholder"));

        // Second round, messageType1, optimism destination
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverOptimism,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        vm.expectEmit(true, true, true, false);
        emit MessageSent(optimismDestSelector, messageHashType1, keccak256("placeholder"));

        // Third round, messageType2, base destination
        vm.expectEmit(true, true, true, false);
        emit CCIPSendRequested(
            EVM2EVMMessage({
                sourceChainSelector: 1,
                sender: address(this),
                receiver: destChainReceiverBase,
                sequenceNumber: 1,
                gasLimit: gasLimit,
                strict: false,
                nonce: 1,
                feeToken: address(0),
                feeTokenAmount: 1,
                data: message1,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                sourceTokenData: new bytes[](0),
                messageId: ""
            })
        );

        // Don't have ccipMessageId at this point, just checking for signature and empty topics.
        vm.expectEmit(true, true, true, false);
        emit MessageSent(optimismDestSelector, messageHashType2, keccak256("placeholder"));

        messageProxy.resendLastMessage{ value: expectedTotalFee }(retryArgs);

        assertEq(address(messageProxy).balance, messageProxyStoredBalance, "messageProxyBalance");
        assertEq(weth.balanceOf(baseOnRamp), baseOnRampBalanceBefore + baseTotalExpectedFee, "baseOnRampBalance");
        assertEq(
            weth.balanceOf(optimismOnRamp), optimismOnRampBalanceBefore + optimismExpectedFee, "optimismOnRampBalance"
        );
        assertEq(messageProxy.lastMessageSent(address(this), messageType1), messageHashType1, "message1Hash");
        assertEq(messageProxy.lastMessageSent(address(this), messageType2), messageHashType2, "message2Hash");
    }
}
