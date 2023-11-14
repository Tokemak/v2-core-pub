// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
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

contract LSTCalculatorBaseDiscountTimestamp is Test {
    SystemRegistry private systemRegistry;
    AccessController private accessController;
    RootPriceOracle private rootPriceOracle;

    TestLSTCalculator private testCalculator;
    address private mockToken = vm.addr(1);
    ILSTStats.LSTStatsData private stats;

    uint256 private constant START_BLOCK = 17_371_713;
    uint256 private constant START_TIMESTAMP = 1_685_449_343;
    uint256 private constant END_BLOCK = 17_393_019;
    uint256 private constant END_TIMESTAMP = 1_686_486_143;

    // dates
    // ['2023-06-02', '2023-06-03', '2023-06-04', '2023-06-05',
    //  '2023-06-06', '2023-06-07', '2023-06-08', '2023-06-09',
    //  '2023-06-10', '2023-06-11', '2023-06-12', '2023-06-13',
    //  '2023-06-14', '2023-06-15', '2023-06-16']

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

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), START_BLOCK);
        vm.selectFork(mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        testCalculator = new TestLSTCalculator(systemRegistry);

        mockCalculateEthPerToken(1); // mock starting value doesn't matter
        mockIsRebasing(false);
        initCalculator(1e18);
    }

    //######################################## Test Discount Sizes ########################################

    function testBelowThresholdOneTimeDiscount() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(9e15)); // .9% just under the 1% threshold
        testCalculator.snapshot();
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [uint40(0), uint40(0), uint40(0), uint40(0), uint40(0)], stats.discountTimestampByPercent
        );
    }

    function testAtThresholdOneTimeDiscount() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent([timestamps[1], 0, 0, 0, 0], stats.discountTimestampByPercent);
    }

    function testMediumOneTimeDiscount() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(25e15)); // 2.5%
        testCalculator.snapshot();
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent([timestamps[1], timestamps[1], 0, 0, 0], stats.discountTimestampByPercent);
    }

    function testLargeOneTimeDiscount() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(50e15)); // 5%
        testCalculator.snapshot();
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], timestamps[1]],
            stats.discountTimestampByPercent
        );
    }

    // ######################################## Test Increasing Discount ########################################

    function testIncreasingDiscountOneSubstantialIncrease() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        setBlockAndTimestamp(2);
        setDiscount(int256(20e15)); // 2%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent([timestamps[1], timestamps[2], 0, 0, 0], stats.discountTimestampByPercent);
    }

    function testIncreasingDiscountOneInsignificantIncrease() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        setBlockAndTimestamp(2);
        setDiscount(int256(15e15)); // 1.5%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent([timestamps[1], 0, 0, 0, 0], stats.discountTimestampByPercent);
    }

    function testIncreasingDiscountTwoSignificantIncrease() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        setBlockAndTimestamp(2);
        setDiscount(int256(20e15)); // 2%
        testCalculator.snapshot();

        setBlockAndTimestamp(3);
        setDiscount(int256(30e15)); // 3%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[2], timestamps[3], 0, 0], stats.discountTimestampByPercent
        );
    }

    // ######################################## Test Decreasing Discount ########################################

    function testDecreasingDiscountSignificantDecrease() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(40e15)); // 4%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(2);
        setDiscount(int256(20e15)); // 2%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(4);
        setDiscount(int256(0)); // 0%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );
    }

    function testDecreasingDiscountInsignificantDecrease() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(40e15)); // 4%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(2);
        setDiscount(int256(39e15)); // 3.9%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(38e15)); // 3.8%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(4);
        setDiscount(int256(37e15)); // 3.7%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );
    }

    // ######################################## Test Jittering ########################################

    function testJitterHighZeroLow() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(30e15)); // 3%
        testCalculator.snapshot();

        setBlockAndTimestamp(2);
        setDiscount(int256(0)); // 0%
        testCalculator.snapshot();

        stats = testCalculator.current();

        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], 0, 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[3], timestamps[1], timestamps[1], 0, 0], stats.discountTimestampByPercent
        );
    }

    function testJitterHighLowHigh() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(40e15)); // 4%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(2);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], timestamps[1], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(30e15)); // 3%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[3], timestamps[3], timestamps[1], 0], stats.discountTimestampByPercent
        );
    }

    function testJitterLowHighLow() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();

        verifyDiscountTimestampByPercent([timestamps[1], 0, 0, 0, 0], stats.discountTimestampByPercent);

        setBlockAndTimestamp(2);
        setDiscount(int256(40e15)); // 4%
        testCalculator.snapshot();

        stats = testCalculator.current();

        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[2], timestamps[2], timestamps[2], 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(10e15)); // 1%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[2], timestamps[2], timestamps[2], 0], stats.discountTimestampByPercent
        );
    }

    function testJitterAroundMedium() public {
        setBlockAndTimestamp(1);
        setDiscount(int256(30e15)); // 3%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], 0, 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(2);
        setDiscount(int256(32e15)); // 3.2%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], 0, 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(3);
        setDiscount(int256(29e15)); // 2.9%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[1], 0, 0], stats.discountTimestampByPercent
        );

        setBlockAndTimestamp(4);
        setDiscount(int256(32e15)); // 3.2%
        testCalculator.snapshot();

        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [timestamps[1], timestamps[1], timestamps[4], 0, 0], stats.discountTimestampByPercent
        );
    }

    // ######################################## Helper Method Tests ########################################

    function testSetDisount() public {
        int256 onePercent = 1e16;
        setDiscount(onePercent);
        verifyDiscount(onePercent);

        int256 zeroPercent = 0;
        setDiscount(zeroPercent);
        verifyDiscount(zeroPercent);

        int256 hundredPercent = 100e16;
        setDiscount(hundredPercent);
        verifyDiscount(hundredPercent);
    }

    function testZeroDiscounts() public {
        stats = testCalculator.current();
        verifyDiscountTimestampByPercent(
            [uint40(0), uint40(0), uint40(0), uint40(0), uint40(0)], stats.discountTimestampByPercent
        );
    }

    // ######################################## Helper Methods ########################################

    function verifyDiscountTimestampByPercent(uint40[5] memory expected, uint40[5] memory actual) private {
        for (uint256 i = 0; i < 5; i += 1) {
            assertEq(actual[i], expected[i], "expected != actual");
        }
    }

    function setDiscount(int256 desiredDiscount) private {
        require(desiredDiscount >= 0, "desiredDiscount < 0");
        //  1e16 == 1% discount
        mockCalculateEthPerToken(100e16);
        mockTokenPrice(uint256(int256(100e16) - desiredDiscount));
    }

    function verifyDiscount(int256 expectedDiscount) private {
        require(expectedDiscount >= 0, "expectedDiscount < 0");
        int256 foundDiscount = testCalculator.current().discount;
        assertEq(foundDiscount, expectedDiscount);
    }

    function setBlockAndTimestamp(uint256 index) private {
        require(index < 5, "index too large");
        vm.roll(uint256(blocksToCheck[index]));
        vm.warp(uint256(timestamps[index]));
    }

    function initCalculator(uint256 initPrice) private {
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: mockToken });
        mockTokenPrice(initPrice);
        testCalculator.initialize(dependantAprs, abi.encode(initData));
    }

    function mockCalculateEthPerToken(uint256 amount) private {
        vm.mockCall(mockToken, abi.encodeWithSelector(MockToken.getValue.selector), abi.encode(amount));
    }

    function mockIsRebasing(bool value) private {
        vm.mockCall(mockToken, abi.encodeWithSelector(MockToken.isRebasing.selector), abi.encode(value));
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

contract TestLSTCalculator is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    function calculateEthPerToken() public view override returns (uint256) {
        // always mock the value
        return MockToken(lstTokenAddress).getValue();
    }

    function isRebasing() public view override returns (bool) {
        // always mock the value
        return MockToken(lstTokenAddress).isRebasing();
    }
}
