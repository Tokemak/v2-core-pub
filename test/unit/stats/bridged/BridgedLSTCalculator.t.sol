// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable gas-custom-errors,avoid-low-level-calls,func-name-mixedcase,max-line-length

import { Test } from "forge-std/Test.sol";

import { BridgedLSTCalculator } from "src/stats/calculators/bridged/BridgedLSTCalculator.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Stats } from "src/stats/Stats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { Errors } from "src/utils/Errors.sol";
import { MessageProxy, IRouterClient } from "src/messageProxy/MessageProxy.sol";
import { EthPerTokenStore } from "src/stats/calculators/bridged/EthPerTokenStore.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";

contract BridgedLSTCalculatorTests is Test {
    SystemRegistry private systemRegistry;
    AccessController private accessController;
    RootPriceOracle private rootPriceOracle;
    MessageProxy private messageProxy;
    address private chainlinkRouter;

    TestCalculator private testCalculator;
    address private mockToken = vm.addr(1);
    address private ethPerTokenStore = makeAddr("ethPerTokenStore");
    address private receivingRouter;
    ILSTStats.LSTStatsData private stats; // TODO: remove shadowed declaration

    uint256 private constant START_BLOCK = 17_371_713;
    uint256 private constant START_TIMESTAMP = 1_685_449_343;
    uint256 private constant END_BLOCK = 17_393_019;
    uint256 private constant END_TIMESTAMP = 1_686_486_143;

    uint24[10] private foundDiscountHistory =
        [uint24(0), uint24(0), uint24(0), uint24(0), uint24(0), uint24(0), uint24(0), uint24(0), uint24(0), uint24(0)];

    uint256[15] private blocksToCheck = [
        17_403_555,
        17_410_645,
        17_417_719,
        17_424_814,
        17_431_903,
        17_438_980,
        17_446_080,
        17_453_185,
        17_460_280,
        17_467_375
    ];

    // 2023-06-02 to 2023-06-16
    uint40[15] private timestamps = [
        uint40(1_685_836_799),
        uint40(1_685_923_199),
        uint40(1_686_009_599),
        uint40(1_686_095_999),
        uint40(1_686_182_399),
        uint40(1_686_268_799),
        uint40(1_686_355_199),
        uint40(1_686_441_599),
        uint40(1_686_527_999),
        uint40(1_686_614_399),
        uint40(1_686_700_799),
        uint40(1_686_787_199),
        uint40(1_686_873_599),
        uint40(1_686_959_999),
        uint40(1_686_614_291)
    ];

    event BaseAprSnapshotTaken(
        uint256 priorEthPerToken,
        uint256 priorTimestamp,
        uint256 currentEthPerToken,
        uint256 currentTimestamp,
        uint256 priorBaseApr,
        uint256 currentBaseApr
    );

    event DestinationMessageSendSet(bool destinationMessageSend);

    // From MessageProxy
    event MessageSent(uint64 destChainSelector, bytes32 messageHash, bytes32 ccipMessageId);

    event EthPerTokenStoreSet(address store);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), START_BLOCK);
        vm.selectFork(mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        receivingRouter = address(new Blank(address(systemRegistry)));
        systemRegistry.setReceivingRouter(receivingRouter);

        chainlinkRouter = makeAddr("CHAINLINK_ROUTER");
        messageProxy = new MessageProxy(systemRegistry, IRouterClient(chainlinkRouter));

        testCalculator = TestCalculator(Clones.clone(address(new TestCalculator(systemRegistry))));
    }

    function testAprInitIncreaseSnapshot() public {
        // Test initializes the baseApr filter and processes the next snapshot
        // where eth backing increases
        uint256 startingEthPerShare = 1_126_467_900_855_209_627;
        mockCalculateEthPerToken(startingEthPerShare);
        initCalculator(1e18, false, startingEthPerShare);

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), START_TIMESTAMP);
        assertEq(testCalculator.lastBaseAprEthPerToken(), startingEthPerShare);

        uint256 endingEthPerShare = 1_126_897_087_511_522_171;
        uint256 endingTimestamp = START_TIMESTAMP + testCalculator.APR_FILTER_INIT_INTERVAL_IN_SEC();
        vm.warp(endingTimestamp);
        mockCalculateEthPerToken(endingEthPerShare);

        uint256 annualizedApr = Stats.calculateAnnualizedChangeMinZero(
            START_TIMESTAMP, startingEthPerShare, endingTimestamp, endingEthPerShare
        );

        // the starting baseApr is equal to the init value measured over init interval
        uint256 expectedBaseApr = annualizedApr;

        // In the bridged version of this calculator the apr snapshot is triggered
        // via a message
        //testCalculator.snapshot();
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: annualizedApr,
                currentEthPerToken: endingEthPerShare
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        vm.expectEmit(true, true, true, true);
        emit BaseAprSnapshotTaken(
            startingEthPerShare, START_TIMESTAMP, endingEthPerShare, endingTimestamp, 0, expectedBaseApr
        );
        testCalculator.onMessageReceive(msgId, 2, message);
        vm.stopPrank();

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), endingTimestamp);
        assertEq(testCalculator.lastBaseAprEthPerToken(), endingEthPerShare);

        mockCalculateEthPerToken(1e18);
        mockTokenPrice(1e18);

        stats = testCalculator.current();
        assertEq(stats.baseApr, expectedBaseApr);
        assertEq(stats.discount, 0);

        // APR Increase
        startingEthPerShare = 1_126_897_087_511_522_171;

        uint256 postInitTimestamp = START_TIMESTAMP + testCalculator.APR_FILTER_INIT_INTERVAL_IN_SEC();
        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), postInitTimestamp);
        assertEq(testCalculator.lastBaseAprEthPerToken(), startingEthPerShare);

        vm.warp(END_TIMESTAMP);
        endingEthPerShare = 1_127_097_087_511_522_171;
        mockCalculateEthPerToken(endingEthPerShare);

        annualizedApr = Stats.calculateAnnualizedChangeMinZero(
            postInitTimestamp, startingEthPerShare, END_TIMESTAMP, endingEthPerShare
        );

        // the starting baseApr is non-zero so the result is filtered with ALPHA
        expectedBaseApr = (
            ((testCalculator.baseApr() * (1e18 - testCalculator.ALPHA())) + annualizedApr * testCalculator.ALPHA())
                / 1e18
        );

        message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: expectedBaseApr,
                currentEthPerToken: endingEthPerShare
            })
        );
        // testCalculator.snapshot();
        vm.startPrank(receivingRouter);

        vm.expectEmit(true, true, false, false);
        emit BaseAprSnapshotTaken(
            startingEthPerShare,
            postInitTimestamp,
            endingEthPerShare,
            END_TIMESTAMP,
            testCalculator.baseApr(),
            expectedBaseApr
        );
        testCalculator.onMessageReceive(msgId, 3, message);
        vm.stopPrank();

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), END_TIMESTAMP);
        assertEq(testCalculator.lastBaseAprEthPerToken(), endingEthPerShare);

        mockCalculateEthPerToken(1e18);
        mockTokenPrice(1e18);

        stats = testCalculator.current();
        assertEq(stats.baseApr, expectedBaseApr);
        assertEq(stats.discount, 0);
    }

    function testAprInitDecreaseSnapshot() public {
        // Test initializes the baseApr filter and processes the next snapshot
        // where eth backing decreases.
        uint256 startingEthPerShare = 1_126_467_900_855_209_627;
        mockCalculateEthPerToken(startingEthPerShare);
        initCalculator(1e18, false, startingEthPerShare);

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), START_TIMESTAMP);
        assertEq(testCalculator.lastBaseAprEthPerToken(), startingEthPerShare);

        uint256 endingEthPerShare = 1_126_897_087_511_522_171;
        uint256 endingTimestamp = START_TIMESTAMP + testCalculator.APR_FILTER_INIT_INTERVAL_IN_SEC();
        vm.warp(endingTimestamp);
        mockCalculateEthPerToken(endingEthPerShare);

        uint256 annualizedApr = Stats.calculateAnnualizedChangeMinZero(
            START_TIMESTAMP, startingEthPerShare, endingTimestamp, endingEthPerShare
        );

        // the starting baseApr is equal to the init value measured over init interval
        uint256 expectedBaseApr = annualizedApr;

        // In the bridged version of this calculator the apr snapshot is triggered
        // via a message
        //testCalculator.snapshot();
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: annualizedApr,
                currentEthPerToken: endingEthPerShare
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        vm.expectEmit(true, true, true, true);
        emit BaseAprSnapshotTaken(
            startingEthPerShare, START_TIMESTAMP, endingEthPerShare, endingTimestamp, 0, expectedBaseApr
        );
        testCalculator.onMessageReceive(msgId, 2, message);
        vm.stopPrank();

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), endingTimestamp);
        assertEq(testCalculator.lastBaseAprEthPerToken(), endingEthPerShare);

        mockCalculateEthPerToken(1e18);
        mockTokenPrice(1e18);

        stats = testCalculator.current();
        assertEq(stats.baseApr, expectedBaseApr);
        assertEq(stats.discount, 0);

        // APR Decrease
        startingEthPerShare = 1_126_897_087_511_522_171;

        uint256 postInitTimestamp = START_TIMESTAMP + testCalculator.APR_FILTER_INIT_INTERVAL_IN_SEC();
        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), postInitTimestamp);
        assertEq(testCalculator.lastBaseAprEthPerToken(), startingEthPerShare);

        vm.warp(END_TIMESTAMP);
        endingEthPerShare = startingEthPerShare - 1e17;

        mockCalculateEthPerToken(endingEthPerShare);
        assertTrue(testCalculator.shouldSnapshot());

        mockCalculateEthPerToken(endingEthPerShare);

        // the starting baseApr is non-zero so the result is filtered with ALPHA
        // Current value is 0 since current interval ETH backing decreased
        expectedBaseApr =
            (((testCalculator.baseApr() * (1e18 - testCalculator.ALPHA())) + 0 * testCalculator.ALPHA()) / 1e18);

        // testCalculator.snapshot();
        message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: expectedBaseApr,
                currentEthPerToken: endingEthPerShare
            })
        );
        vm.startPrank(receivingRouter);
        testCalculator.onMessageReceive(msgId, 3, message);
        vm.stopPrank();

        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), END_TIMESTAMP);
        assertEq(testCalculator.lastBaseAprEthPerToken(), endingEthPerShare);

        mockCalculateEthPerToken(1e18);
        mockTokenPrice(1e18);

        stats = testCalculator.current();
        assertEq(stats.baseApr, expectedBaseApr);
        assertEq(stats.lastSnapshotTimestamp, END_TIMESTAMP);
        assertEq(stats.discount, 0);
    }

    function testRevertNoSnapshot() public {
        uint256 startingEthPerShare = 1e18;
        mockCalculateEthPerToken(startingEthPerShare);
        initCalculator(1e18, false, startingEthPerShare);

        // move each value forward so we can verify that a snapshot was not taken
        uint256 endingEthPerShare = startingEthPerShare + 1;
        vm.warp(START_TIMESTAMP + 1);
        mockCalculateEthPerToken(endingEthPerShare);
        assertFalse(testCalculator.shouldSnapshot());

        vm.expectRevert(abi.encodeWithSelector(IStatsCalculator.NoSnapshotTaken.selector));
        testCalculator.snapshot();
    }

    function testDiscountShouldCalculateCorrectly() public {
        mockCalculateEthPerToken(1e17); // starting value doesn't matter for these tests
        initCalculator(1e18, false, 1e7);

        int256 expected;

        // test handling a premium with a non-rebasing token
        mockCalculateEthPerToken(1e18);
        mockTokenPrice(11e17);
        testCalculator.setIsRebasing(false);

        expected = 1e18 - int256(11e17 * 1e18) / 1e18;
        stats = testCalculator.current();
        assertEq(stats.discount, expected);

        // test handling a discount with a non-rebasing token
        mockCalculateEthPerToken(11e17);
        mockTokenPrice(1e18);
        testCalculator.setIsRebasing(false);

        expected = 1e18 - int256(1e18 * 1e18) / 11e17;
        stats = testCalculator.current();
        assertEq(stats.discount, expected);

        // test handling a premium for a rebasing token
        // do not mock ethPerToken
        mockTokenPrice(12e17);
        testCalculator.setIsRebasing(true);

        expected = 1e18 - int256(12e17);
        stats = testCalculator.current();
        assertEq(stats.discount, expected);

        // test handling a discount for a rebasing token
        // do not mock ethPerToken
        mockTokenPrice(9e17);
        testCalculator.setIsRebasing(true);

        expected = 1e18 - int256(9e17);
        stats = testCalculator.current();
        assertEq(stats.discount, expected);
    }

    // ##################################### Discount Timestamp Percent Tests #####################################

    function testDiscountTimestampByPercentOnetimeHighestDiscount() public {
        mockCalculateEthPerToken(1);
        initCalculator(1e18, false, 1);
        setBlockAndTimestamp(1);
        setDiscount(int256(50e15)); // 5%
        testCalculator.snapshot();
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(timestamps[1], stats.discountTimestampByPercent);
    }

    function testDiscountTimestampByPercentIncreasingDiscount() public {
        mockCalculateEthPerToken(1);
        initCalculator(1e18, false, 1);

        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(timestamps[1], stats.discountTimestampByPercent);
    }

    function testDiscountTimestampByPercentDecreasingDiscount() public {
        mockCalculateEthPerToken(1);
        initCalculator(1e18, false, 1);

        setBlockAndTimestamp(1);
        setDiscount(int256(40e15)); // 4%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(timestamps[1], stats.discountTimestampByPercent);
    }

    function testDiscountTimestampByPercentJitterHighToZeroToLow() public {
        mockCalculateEthPerToken(1);
        initCalculator(1e18, false, 1);

        setBlockAndTimestamp(1);
        setDiscount(int256(30e15)); // 3%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(timestamps[1], stats.discountTimestampByPercent);

        setBlockAndTimestamp(2);
        setDiscount(int256(0)); // 0%
        testCalculator.snapshot();

        stats = testCalculator.current();

        verifyDiscountTimestampByPercent(0, stats.discountTimestampByPercent);

        setBlockAndTimestamp(3);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(timestamps[3], stats.discountTimestampByPercent);
    }

    function testDiscountTimestampByPercentStartingDiscount() public {
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        setDiscount(50e15);
        setBlockAndTimestamp(0);
        testCalculator.initialize(dependantAprs, abi.encode(initData));
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: 0,
                currentEthPerToken: 100e16
            })
        );
        vm.prank(receivingRouter);
        testCalculator.onMessageReceive(keccak256("LST_SNAPSHOT"), 1, message);

        stats = testCalculator.current();
        assertEq(stats.discountHistory[0], 5e5); // the discount when the contract was initalized() was 5%
        verifyDiscountTimestampByPercent(timestamps[0], stats.discountTimestampByPercent);
    }

    // ############################## discount history tests ##################################

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_DiscountHistoryExistingDiscountAtContractDeployment(bool rebase) public {
        setBlockAndTimestamp(1);
        mockCalculateEthPerToken(100e16);
        initCalculator(99e16, rebase, 100e16);
        stats = testCalculator.current();
        foundDiscountHistory = [1e5, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        verifyDiscountHistory(stats.discountHistory, foundDiscountHistory);
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_DiscountHistoryPremiumRecordedAsZeroDiscount(bool rebase) public {
        mockCalculateEthPerToken(100e16);
        initCalculator(110e16, rebase, 100e16);
        setBlockAndTimestamp(1);
        testCalculator.snapshot();
        stats = testCalculator.current();
        foundDiscountHistory = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        verifyDiscountHistory(stats.discountHistory, foundDiscountHistory);
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_DiscountHistoryHighDiscount(bool rebase) public {
        mockCalculateEthPerToken(100e16);
        initCalculator(100e16, rebase, 100e16);

        setBlockAndTimestamp(1);
        setDiscount(100e16); // 100% discount

        testCalculator.snapshot();
        stats = testCalculator.current();
        foundDiscountHistory = [0, 100e5, 0, 0, 0, 0, 0, 0, 0, 0];
        verifyDiscountHistory(stats.discountHistory, foundDiscountHistory);
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_DiscountHistoryWrapAround(bool rebase) public {
        mockCalculateEthPerToken(100e16);
        initCalculator(100e16, rebase, 100e16);
        for (uint256 i = 1; i < 14; i += 1) {
            setBlockAndTimestamp(i);
            setDiscount(int256(i * 1e16));
            testCalculator.snapshot();
        }
        stats = testCalculator.current();
        foundDiscountHistory = [10e5, 11e5, 12e5, 13e5, 4e5, 5e5, 6e5, 7e5, 8e5, 9e5];
        verifyDiscountHistory(stats.discountHistory, foundDiscountHistory);
    }

    // ############################## Destination send logic ########################################

    function test_SendMessageToProxy_NotAllowed() public {
        mockCalculateEthPerToken(1);
        initCalculator(1e18, false, 1);

        // Warp timestamp to time that allows branch needed for message send to other chain to run
        vm.warp(block.timestamp + testCalculator.APR_FILTER_INIT_INTERVAL_IN_SEC() + 1);

        // Mock all roles to return true
        vm.mockCall(address(accessController), abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));

        // Set to true
        vm.expectRevert(abi.encodeWithSelector(Errors.NotSupported.selector));
        testCalculator.setDestinationMessageSend();
    }

    // ############################## L2 Specific Handling ########################################

    function test_SetEthPerTokenStoreUpdatesValue() public {
        accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        address beforeValue = address(testCalculator.ethPerTokenStore());
        address newValue = makeAddr("newEthPerTokenStore");

        testCalculator.setEthPerTokenStore(EthPerTokenStore(newValue));

        assertNotEq(beforeValue, newValue, "newOld");
        assertEq(address(testCalculator.ethPerTokenStore()), newValue, "newQueried");
    }

    function test_SetEthPerTokenStoreEmitsEvent() public {
        accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        address newValue = makeAddr("newEthPerTokenStore");

        vm.expectEmit(true, true, true, true);
        emit EthPerTokenStoreSet(newValue);
        testCalculator.setEthPerTokenStore(EthPerTokenStore(newValue));
    }

    function test_IsRebasingBasedOnInitializationValue() public {
        uint256 snapshot = vm.snapshot();

        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: true,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(testCalculator.isRebasing(), true, "true");

        vm.revertTo(snapshot);

        dependantAprs = new bytes32[](0);
        initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(testCalculator.isRebasing(), false, "false");
    }

    function test_ShouldSnapshotIsFalseUntilFirstMessageReceived() public {
        mockCalculateEthPerToken(1);
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        vm.warp(block.timestamp + 7 weeks);

        assertEq(testCalculator.shouldSnapshot(), false, "false");

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({ snapshotTimestamp: block.timestamp, newBaseApr: 1, currentEthPerToken: 1 })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();

        assertEq(testCalculator.shouldSnapshot(), false, "false2");

        vm.warp(block.timestamp + 1 days);

        assertEq(testCalculator.shouldSnapshot(), true, "true");
    }

    function test_MessageReceiveUpdatesAprAndEthPerToken() public {
        mockCalculateEthPerToken(1);
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(testCalculator.baseApr(), 0, "beginBaseApr");
        assertEq(testCalculator.lastBaseAprEthPerToken(), 0, "beginLastApr");
        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), 0, "beginTimestamp");

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp + 77,
                newBaseApr: 9,
                currentEthPerToken: 10
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();

        assertEq(testCalculator.baseApr(), 9, "endBaseApr");
        assertEq(testCalculator.lastBaseAprEthPerToken(), 10, "endLastApr");
        assertEq(testCalculator.lastBaseAprSnapshotTimestamp(), block.timestamp + 77, "endTimestamp");
    }

    function test_EthPerTokenUsesLocalValueIfNewer() public {
        mockCalculateEthPerToken(1);
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        uint256 storeValue = 1_000_000;
        vm.mockCall(
            ethPerTokenStore,
            abi.encodeWithSelector(EthPerTokenStore.getEthPerToken.selector),
            abi.encode(storeValue, block.timestamp - 1 days)
        );

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp - 1 days + 1,
                newBaseApr: 9,
                currentEthPerToken: storeValue - 1
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();

        assertEq(testCalculator.calculateEthPerToken(), storeValue - 1, "val");
    }

    function test_EthPerTokenUsesStoreValueIfNewer() public {
        mockCalculateEthPerToken(1);
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        uint256 storeValue = 1_000_000;
        vm.mockCall(
            ethPerTokenStore,
            abi.encodeWithSelector(EthPerTokenStore.getEthPerToken.selector),
            abi.encode(storeValue, block.timestamp - 1 days + 1)
        );

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp - 1 days,
                newBaseApr: 9,
                currentEthPerToken: storeValue - 1
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();

        assertEq(testCalculator.calculateEthPerToken(), storeValue, "val");
    }

    function test_EthPerTokenLookupUsesSourceTokenAddress() public {
        mockCalculateEthPerToken(1);
        address sourceToken = makeAddr("sourceToken");
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: sourceToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        uint256 storeValue = 1_000_000;
        vm.mockCall(
            ethPerTokenStore,
            abi.encodeWithSelector(EthPerTokenStore.getEthPerToken.selector, sourceToken),
            abi.encode(storeValue, block.timestamp - 1 days + 1)
        );

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp - 1 days,
                newBaseApr: 9,
                currentEthPerToken: storeValue - 1
            })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();

        assertEq(testCalculator.calculateEthPerToken(), storeValue, "val");
    }

    function test_UpdatesNonce() public {
        mockCalculateEthPerToken(1);
        address sourceToken = makeAddr("sourceToken");
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: sourceToken,
            isRebasing: false,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(1e18);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        uint256 storeValue = 1_000_000;
        vm.mockCall(
            ethPerTokenStore,
            abi.encodeWithSelector(EthPerTokenStore.getEthPerToken.selector, sourceToken),
            abi.encode(storeValue, block.timestamp - 1 days + 1)
        );

        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: 9,
                currentEthPerToken: storeValue
            })
        );

        vm.startPrank(receivingRouter);
        testCalculator.onMessageReceive(MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE, 3, message);
        vm.stopPrank();

        assertEq(testCalculator.lastStoredNonce(), 3);
    }

    function test_RevertIf_UnsupportedMessageReceived() public {
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({ snapshotTimestamp: block.timestamp, newBaseApr: 1, currentEthPerToken: 1 })
        );
        vm.startPrank(receivingRouter);
        bytes32 msgId = keccak256("xxxxxx");
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedMessage.selector, msgId, message));
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();
    }

    function test_RevertIf_ReceivedMessageNotFromRouter() public {
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({ snapshotTimestamp: block.timestamp, newBaseApr: 1, currentEthPerToken: 1 })
        );
        vm.startPrank(makeAddr("X"));
        bytes32 msgId = keccak256("LST_SNAPSHOT");
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        testCalculator.onMessageReceive(msgId, 1, message);
        vm.stopPrank();
    }

    function test_RevertIf_NewEthPerTokenStoreIsZero() public {
        accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newStore"));
        testCalculator.setEthPerTokenStore(EthPerTokenStore(address(0)));
    }

    function test_RevertIf_InvalidRoleForSetEthPerTokenStore() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        testCalculator.setEthPerTokenStore(EthPerTokenStore(address(1)));
    }

    function test_RevertIf_InvalidNonceReceived() public {
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({ snapshotTimestamp: block.timestamp, newBaseApr: 1, currentEthPerToken: 1 })
        );

        uint256 currentStoredNonce = testCalculator.lastStoredNonce();

        vm.startPrank(receivingRouter);
        vm.expectRevert(
            abi.encodeWithSelector(BridgedLSTCalculator.OnlyNewerValue.selector, currentStoredNonce, currentStoredNonce)
        );
        testCalculator.onMessageReceive(MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE, currentStoredNonce, message);
        vm.stopPrank();
    }

    // ############################## helper functions ########################################

    function setDiscount(int256 desiredDiscount) private {
        require(desiredDiscount >= 0, "desiredDiscount < 0");
        //  1e16 == 1% discount
        mockCalculateEthPerToken(100e16);
        mockTokenPrice(uint256(int256(100e16) - desiredDiscount));
    }

    function setBlockAndTimestamp(uint256 index) private {
        vm.roll(uint256(blocksToCheck[index]));
        vm.warp(uint256(timestamps[index]));
    }

    function verifyDiscountHistory(uint24[10] memory actual, uint24[10] memory expected) public {
        for (uint8 i = 0; i < 10; i++) {
            assertEq(actual[i], expected[i]);
        }
    }

    function verifyDiscountTimestampByPercent(uint40 expected, uint40 actual) private {
        assertEq(actual, expected, "expected != actual");
    }

    function verifyDiscount(int256 expectedDiscount) private {
        require(expectedDiscount >= 0, "expectedDiscount < 0");
        int256 foundDiscount = testCalculator.current().discount;
        assertEq(foundDiscount, expectedDiscount);
    }

    function initCalculator(uint256 initPrice, bool isRebasing, uint256 initialEthPerShare) private {
        bytes32[] memory dependantAprs = new bytes32[](0);
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: mockToken,
            sourceTokenAddress: mockToken,
            isRebasing: isRebasing,
            ethPerTokenStore: ethPerTokenStore
        });
        mockTokenPrice(initPrice);
        testCalculator.initialize(dependantAprs, abi.encode(initData));

        // These tests are all setup expecting the state as it was previously
        // Which was on init it would have initial ethPerToken values
        // Ensure we have those
        bytes memory message = abi.encode(
            MessageTypes.LSTDestinationInfo({
                snapshotTimestamp: block.timestamp,
                newBaseApr: 0,
                currentEthPerToken: initialEthPerShare
            })
        );
        vm.prank(receivingRouter);
        testCalculator.onMessageReceive(keccak256("LST_SNAPSHOT"), 1, message);
    }

    function mockCalculateEthPerToken(uint256 amount) private {
        // Tests assume this value is always used so we set the timestamp to be max so its always picked
        vm.mockCall(
            ethPerTokenStore,
            abi.encodeWithSelector(EthPerTokenStore.getEthPerToken.selector),
            abi.encode(amount, uint256(type(uint48).max))
        );
    }

    function mockTokenPrice(uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, mockToken),
            abi.encode(price)
        );
    }
}

interface MockToken {
    function getValue() external view returns (uint256);
    function isRebasing() external view returns (bool);
}

contract TestCalculator is BridgedLSTCalculator {
    constructor(ISystemRegistry _systemRegistry) BridgedLSTCalculator(_systemRegistry) { }

    function setIsRebasing(bool isRebasing) external {
        _isRebasing = isRebasing;
    }
}

contract Blank {
    address public getSystemRegistry;

    constructor(address sysReg) {
        getSystemRegistry = sysReg;
    }
}
