// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Strings } from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { Stats } from "src/stats/Stats.sol";

contract IncentivePricingTest is Test {
    uint256 private constant TARGET_BLOCK = 17_580_732;
    uint256 private constant TARGET_BLOCK_TIMESTAMP = 1_687_990_535;

    address private immutable unauthorizedAddr = vm.addr(1001);

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    RootPriceOracle private rootPriceOracle;
    IncentivePricingStats private pricingStats;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event TokenSnapshot(
        address indexed token,
        uint40 lastSnapshot,
        uint256 fastFilterPrice,
        uint256 slowFilterPrice,
        uint256 initCount,
        bool initComplete
    );

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), TARGET_BLOCK);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));
        accessController.grantRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, address(this));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        pricingStats = new IncentivePricingStats(systemRegistry);
    }

    function testSetRegisteredTokenRevertIfUnauthorized() public {
        vm.prank(unauthorizedAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MissingRole.selector, Roles.STATS_INCENTIVE_TOKEN_UPDATER, unauthorizedAddr)
        );
        pricingStats.setRegisteredToken(vm.addr(1));
    }

    function testSetRegisteredTokenRevertIfNotRegisteredWithOracle() public {
        address token = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingTokenOracle.selector, token));
        pricingStats.setRegisteredToken(token);
    }

    function testSetRegisteredTokenRevertIfDuplicate() public {
        address token = vm.addr(1);
        registerToken(token, 1e18);

        vm.expectRevert(abi.encodeWithSelector(IIncentivesPricingStats.TokenAlreadyRegistered.selector, token));
        pricingStats.setRegisteredToken(token);
    }

    function testSetRegisteredTokenSuccessful() public {
        address token = vm.addr(1);
        uint256 price = 1e18;

        vm.expectEmit(true, true, true, true);
        emit TokenAdded(token);

        registerToken(token, price);

        (address[] memory tokens, IIncentivesPricingStats.TokenSnapshotInfo[] memory allInfo) =
            pricingStats.getTokenPricingInfo();

        assertEq(tokens.length, 1);
        assertEq(allInfo.length, 1);

        IIncentivesPricingStats.TokenSnapshotInfo memory info = allInfo[0];

        assertEq(tokens[0], token);
        assertEq(info.lastSnapshot, TARGET_BLOCK_TIMESTAMP);
        assertEq(info._initCount, 1);
        assertEq(info._initAcc, price);
        assertEq(info.slowFilterPrice, 0);
        assertEq(info.fastFilterPrice, 0);
        assertFalse(info._initComplete);
    }

    function testRemoveRegisteredTokenRevertIfUnauthorized() public {
        vm.prank(unauthorizedAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MissingRole.selector, Roles.STATS_INCENTIVE_TOKEN_UPDATER, unauthorizedAddr)
        );
        pricingStats.removeRegisteredToken(vm.addr(1));
    }

    function testRemoveRegisteredTokenSuccessful() public {
        address token = vm.addr(2);
        uint256 price = 1e18;
        registerToken(token, price);

        vm.expectEmit(true, true, true, true);
        emit TokenRemoved(token);

        pricingStats.removeRegisteredToken(token);

        (address[] memory tokens, IIncentivesPricingStats.TokenSnapshotInfo[] memory allInfo) =
            pricingStats.getTokenPricingInfo();

        assertEq(tokens.length, 0);
        assertEq(allInfo.length, 0);
    }

    function testGetRegisteredTokens() public {
        address[] memory inputTokens = new address[](3);
        inputTokens[0] = vm.addr(1);
        inputTokens[1] = vm.addr(2);
        inputTokens[2] = vm.addr(3);

        address[] memory tokens;

        tokens = pricingStats.getRegisteredTokens();
        assertEq(tokens.length, 0);

        registerToken(inputTokens[0], 1e18);
        tokens = pricingStats.getRegisteredTokens();
        assertEq(tokens.length, 1);
        assertAddressInList(inputTokens[0], tokens);

        registerToken(inputTokens[1], 1e17);
        registerToken(inputTokens[2], 1e17);
        tokens = pricingStats.getRegisteredTokens();
        assertEq(tokens.length, 3);
        assertAddressInList(inputTokens[0], tokens);
        assertAddressInList(inputTokens[1], tokens);
        assertAddressInList(inputTokens[2], tokens);

        pricingStats.removeRegisteredToken(vm.addr(2));
        tokens = pricingStats.getRegisteredTokens();
        assertEq(tokens.length, 2);
        assertAddressInList(inputTokens[0], tokens);
        assertAddressInList(inputTokens[2], tokens);
    }

    function testGetTokenPricingInfo() public {
        address[] memory inputTokens = new address[](3);
        inputTokens[0] = vm.addr(1);
        inputTokens[1] = vm.addr(2);
        inputTokens[2] = vm.addr(3);

        address[] memory tokens;
        IIncentivesPricingStats.TokenSnapshotInfo[] memory allInfo;

        (tokens, allInfo) = pricingStats.getTokenPricingInfo();
        assertEq(tokens.length, 0);
        assertEq(allInfo.length, 0);

        registerToken(inputTokens[0], 1e18);
        (tokens, allInfo) = pricingStats.getTokenPricingInfo();
        assertEq(tokens.length, 1);
        assertEq(allInfo.length, 1);
        assertAddressInList(inputTokens[0], tokens);

        registerToken(inputTokens[1], 1e17);
        registerToken(inputTokens[2], 1e17);
        (tokens, allInfo) = pricingStats.getTokenPricingInfo();
        assertEq(tokens.length, 3);
        assertEq(allInfo.length, 3);
        assertAddressInList(inputTokens[0], tokens);
        assertAddressInList(inputTokens[1], tokens);
        assertAddressInList(inputTokens[2], tokens);

        pricingStats.removeRegisteredToken(inputTokens[1]);
        tokens = pricingStats.getRegisteredTokens();
        assertEq(tokens.length, 2);
        assertAddressInList(inputTokens[0], tokens);
        assertAddressInList(inputTokens[2], tokens);
    }

    function testSnapshotShouldRevertIfUnauthorized() public {
        address[] memory tokens = new address[](0);
        vm.prank(unauthorizedAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MissingRole.selector, Roles.STATS_SNAPSHOT_ROLE, unauthorizedAddr)
        );
        pricingStats.snapshot(tokens);
    }

    function testSnapshotShouldRevertListEmpty() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "tokensToSnapshot"));
        pricingStats.snapshot(tokens);
    }

    function testSnapshotShouldRevertIfTokenNotFound() public {
        address[] memory tokens = new address[](1);
        tokens[0] = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(IIncentivesPricingStats.TokenNotFound.selector, tokens[0]));
        pricingStats.snapshot(tokens);
    }

    function testSnapshotShouldRevertIfTokenIsZero() public {
        address[] memory tokens = new address[](1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        pricingStats.snapshot(tokens);
    }

    function testSnapshotSuccessful() public {
        address token = vm.addr(1);
        uint256 startingPrice = 45e17;
        registerToken(token, startingPrice);

        address[] memory tokens;
        IIncentivesPricingStats.TokenSnapshotInfo[] memory allInfo;

        uint256[] memory prices = new uint256[](8);
        prices[0] = 47e17;
        prices[1] = 75e17;
        prices[2] = 30e17;
        prices[3] = 20e17;
        prices[4] = 50e17;
        prices[5] = 10e17;
        prices[6] = 47e17;
        prices[7] = 99e17;
        uint256 lastTimestamp = updateTokenPrice(TARGET_BLOCK_TIMESTAMP, token, prices);

        // at this point were still in the init phase
        (tokens, allInfo) = pricingStats.getTokenPricingInfo();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(allInfo.length, 1);

        // calculated manually
        uint256 expectedPriceSum = 42_300_000_000_000_000_000;

        assertEq(allInfo[0]._initCount, 9);
        assertEq(allInfo[0]._initAcc, expectedPriceSum);
        assertEq(allInfo[0].fastFilterPrice, 0);
        assertEq(allInfo[0].slowFilterPrice, 0);
        assertEq(allInfo[0].lastSnapshot, lastTimestamp);
        assertFalse(allInfo[0]._initComplete);

        prices = new uint256[](9);
        prices[0] = 87e17;
        prices[1] = 10e17;
        prices[2] = 50e17;
        prices[3] = 8e17;
        prices[4] = 70e17;
        prices[5] = 35e17;
        prices[6] = 40e17;
        prices[7] = 19e17;
        prices[8] = 30e17;
        lastTimestamp = updateTokenPrice(lastTimestamp, token, prices);

        // at this point we just completed the init phase
        (tokens, allInfo) = pricingStats.getTokenPricingInfo();

        // calculated manually
        expectedPriceSum += 34_900_000_000_000_000_000;
        uint256 expectedPrice = 4_288_888_888_888_888_888;
        assertEq(expectedPrice, expectedPriceSum / 18);

        assertEq(allInfo[0]._initCount, 18);
        assertEq(allInfo[0]._initAcc, expectedPriceSum);
        assertEq(allInfo[0].fastFilterPrice, expectedPrice);
        assertEq(allInfo[0].slowFilterPrice, expectedPrice);
        assertEq(allInfo[0].lastSnapshot, lastTimestamp);
        assertTrue(allInfo[0]._initComplete);

        prices = new uint256[](1);
        prices[0] = 1e10;
        lastTimestamp += pricingStats.MIN_INTERVAL();
        vm.warp(lastTimestamp);
        mockTokenPrice(token, prices[0]);

        address[] memory tokensToSnapshot = new address[](1);
        tokensToSnapshot[0] = token;

        uint256 fastAlpha = pricingStats.FAST_ALPHA();
        uint256 slowAlpha = pricingStats.SLOW_ALPHA();
        uint256 expectedFast = Stats.getFilteredValue(fastAlpha, expectedPrice, prices[0]);
        uint256 expectedSlow = Stats.getFilteredValue(slowAlpha, expectedPrice, prices[0]);

        vm.expectEmit(true, true, true, true);
        emit TokenSnapshot(token, uint40(lastTimestamp), expectedFast, expectedSlow, 18, true);

        pricingStats.snapshot(tokensToSnapshot);

        // now we're updating the filter values
        (tokens, allInfo) = pricingStats.getTokenPricingInfo();
        assertEq(allInfo[0]._initCount, 18);
        assertEq(allInfo[0]._initAcc, expectedPriceSum);
        assertEq(allInfo[0].lastSnapshot, lastTimestamp);
        assertTrue(allInfo[0]._initComplete);
        assertEq(allInfo[0].fastFilterPrice, expectedFast);
        assertEq(allInfo[0].slowFilterPrice, expectedSlow);
    }

    function testGetPriceShouldRevertIfTokenNotRegistered() public {
        address token = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(IIncentivesPricingStats.TokenNotFound.selector, token));
        pricingStats.getPrice(token, 0);
    }

    function testGetPriceShouldRevertIfStale() public {
        address token = vm.addr(1);
        uint256 price = 55e17;
        registerToken(token, price);

        vm.warp(TARGET_BLOCK_TIMESTAMP + 1);
        vm.expectRevert(abi.encodeWithSelector(IIncentivesPricingStats.IncentiveTokenPriceStale.selector, token));
        pricingStats.getPrice(token, 0);
    }

    function testGetPriceSuccessful() public {
        address token = vm.addr(1);
        uint256 startingPrice = 45e17;
        registerToken(token, startingPrice);

        uint256[] memory prices = new uint256[](17);
        prices[0] = 47e17;
        prices[1] = 75e17;
        prices[2] = 30e17;
        prices[3] = 20e17;
        prices[4] = 50e17;
        prices[5] = 10e17;
        prices[6] = 47e17;
        prices[7] = 99e17;
        prices[8] = 87e17;
        prices[9] = 10e17;
        prices[10] = 50e17;
        prices[11] = 8e17;
        prices[12] = 70e17;
        prices[13] = 35e17;
        prices[14] = 40e17;
        prices[15] = 19e17;
        prices[16] = 30e17;

        uint256 timestamp = updateTokenPrice(TARGET_BLOCK_TIMESTAMP, token, prices);

        // manually calculated
        uint256 expectedPrice = 4_288_888_888_888_888_888;

        (uint256 fastPrice, uint256 slowPrice) = pricingStats.getPrice(token, 100);
        assertEq(fastPrice, expectedPrice);
        assertEq(slowPrice, expectedPrice);

        prices = new uint256[](1);
        prices[0] = 25e16;

        timestamp = updateTokenPrice(block.timestamp, token, prices);
        (fastPrice, slowPrice) = pricingStats.getPrice(token, 100);

        uint256 fastAlpha = pricingStats.FAST_ALPHA();
        uint256 slowAlpha = pricingStats.SLOW_ALPHA();

        uint256 expectedFast = Stats.getFilteredValue(fastAlpha, expectedPrice, prices[0]);
        assertEq(fastPrice, expectedFast);

        uint256 expectedSlow = Stats.getFilteredValue(slowAlpha, expectedPrice, prices[0]);
        assertEq(slowPrice, expectedSlow);
    }

    function testSetPriceCalcsAreAccurate() public {
        address token = vm.addr(1);
        uint256 startingPrice = 45e17;
        registerToken(token, startingPrice);

        uint256[] memory prices = new uint256[](17);
        // put in the same number repeatedly
        // expected ending average will be the startingPrice
        for (uint256 i = 0; i < prices.length; ++i) {
            prices[i] = startingPrice;
        }

        updateTokenPrice(TARGET_BLOCK_TIMESTAMP, token, prices);
        (uint256 fastPrice, uint256 slowPrice) = pricingStats.getPrice(token, 100);
        assertEq(fastPrice, startingPrice);
        assertEq(slowPrice, startingPrice);
    }

    function registerToken(address token, uint256 initialPrice) internal {
        mockTokenPrice(token, initialPrice);
        pricingStats.setRegisteredToken(token);
    }

    function updateTokenPrice(uint256 timestamp, address token, uint256[] memory prices) internal returns (uint256) {
        uint256 numUpdates = prices.length;
        uint256 _timestamp = timestamp;

        address[] memory tokensToSnapshot = new address[](1);
        tokensToSnapshot[0] = token;

        for (uint256 i = 0; i < numUpdates; ++i) {
            _timestamp += pricingStats.MIN_INTERVAL();
            vm.warp(_timestamp);
            mockTokenPrice(token, prices[i]);

            vm.expectEmit(true, true, true, false); // not checking data
            emit TokenSnapshot(token, 0, 0, 0, 0, false);

            pricingStats.snapshot(tokensToSnapshot);
        }

        return _timestamp;
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function assertAddressInList(address target, address[] memory list) internal {
        for (uint256 i = 0; i < list.length; ++i) {
            if (list[i] == target) {
                return;
            }
        }

        string memory addr = Strings.toHexString(uint160(target), 20);
        fail(string.concat(addr, " not in list"));
    }
}
