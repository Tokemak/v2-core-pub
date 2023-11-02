// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { TELLOR_ORACLE, RETH_MAINNET, RETH_CL_FEED_MAINNET } from "test/utils/Addresses.sol";

import { TellorOracle, BaseOracleDenominations, UsingTellor } from "src/oracles/providers/TellorOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Errors } from "src/utils/Errors.sol";

import { TellorPlayground } from "lib/usingtellor/contracts/TellorPlayground.sol";

contract TellorOracleTest is Test {
    // Eth - usd query id
    bytes32 public constant QUERY_ID = 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992;
    // 10k Eth, should never return higher as Eth has never cost this much at pinned blocks.
    uint256 public constant ETH_MAX_USD = 10_000_000_000_000_000_000_000;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ISystemRegistry public systemRegistry;
    TellorOracle public _oracle;

    error AccessDenied();
    error InvalidPricingTimeout(uint256 pricingTimeout);

    event TellorRegistrationAdded(address token, BaseOracleDenominations.Denomination, bytes32 _queryId);
    event TellorRegistrationRemoved(address token, bytes32 queryId);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_200_000);

        systemRegistry = ISystemRegistry(address(777));
        AccessController accessControl = new AccessController(address(systemRegistry));
        IRootPriceOracle rootPriceOracle = IRootPriceOracle(vm.addr(324));
        generateSystemRegistry(address(systemRegistry), address(accessControl), address(rootPriceOracle));
        _oracle = new TellorOracle(systemRegistry, TELLOR_ORACLE);

        vm.makePersistent(address(systemRegistry));
        vm.makePersistent(address(accessControl));
    }

    // Test `addTellorRegistration()`.
    function test_RevertNonOwnerQueryId() external {
        vm.expectRevert(AccessDenied.selector);
        vm.prank(address(3));

        _oracle.addTellorRegistration(address(1), bytes32("Test Bytes"), BaseOracleDenominations.Denomination.ETH, 0);
    }

    function test_ZeroAddressRevert_AddTellorRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenForQueryId"));

        _oracle.addTellorRegistration(address(0), bytes32("Test Bytes"), BaseOracleDenominations.Denomination.ETH, 0);
    }

    function test_ZeroBytesRevert_AddTellorRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "queryId"));

        _oracle.addTellorRegistration(address(1), bytes32(0), BaseOracleDenominations.Denomination.ETH, 0);
    }

    function test_RevertAlreadySet_AddTellorRegistration() external {
        _oracle.addTellorRegistration(address(1), bytes32("Test Bytes"), BaseOracleDenominations.Denomination.ETH, 0);

        vm.expectRevert(Errors.MustBeZero.selector);

        _oracle.addTellorRegistration(address(1), bytes32("Test Bytes 2"), BaseOracleDenominations.Denomination.ETH, 0);
    }

    function test_RevertPricingTimeoutTooSmall() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPricingTimeout.selector, 1 minutes));

        _oracle.addTellorRegistration(
            address(1), bytes32("Test Bytes"), BaseOracleDenominations.Denomination.ETH, 1 minutes
        );
    }

    function test_ProperAddTellorRegistration() external {
        vm.expectEmit(false, false, false, true);
        emit TellorRegistrationAdded(address(1), BaseOracleDenominations.Denomination.ETH, bytes32("Test Byte"));

        _oracle.addTellorRegistration(address(1), bytes32("Test Byte"), BaseOracleDenominations.Denomination.ETH, 0);

        assertEq(_oracle.getQueryInfo(address(1)).queryId, bytes32("Test Byte"));
    }

    // Test `removeTellorRegistration()`
    function test_RevertNonOwner() external {
        vm.prank(address(2));
        vm.expectRevert(AccessDenied.selector);

        _oracle.removeTellorRegistration(address(1));
    }

    function test_RevertZeroAddressToken_RemoveTellorRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenToRemoveRegistration"));

        _oracle.removeTellorRegistration(address(0));
    }

    function test_QueryIdZeroBytes_RemoveTellorRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "queryIdBeforeDeletion"));

        _oracle.removeTellorRegistration(address(1));
    }

    function test_ProperRemoveTellorRegistration() external {
        _oracle.addTellorRegistration(address(1), bytes32("Test Bytes"), BaseOracleDenominations.Denomination.ETH, 0);

        assertEq(_oracle.getQueryInfo(address(1)).queryId, bytes32("Test Bytes"));

        vm.expectEmit(false, false, false, true);
        emit TellorRegistrationRemoved(address(1), bytes32("Test Bytes"));

        _oracle.removeTellorRegistration(address(1));

        assertEq(_oracle.getQueryInfo(address(1)).queryId, bytes32(0));
    }

    // test `getPrice()`
    function test_RevertInvalidDataReturned() external {
        _oracle.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        // Returns timestamp of 0
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(UsingTellor.getDataBefore.selector),
            abi.encode(true, abi.encode(1), 0)
        );
        vm.expectRevert(BaseOracleDenominations.InvalidDataReturned.selector);
        _oracle.getPriceInEth(ETH);

        // Returns price of zero
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(UsingTellor.getDataBefore.selector),
            abi.encode(true, abi.encode(0), block.timestamp - 30 minutes)
        );
        vm.expectRevert(BaseOracleDenominations.InvalidDataReturned.selector);
        _oracle.getPriceInEth(ETH);
    }

    function test_RevertsInvalidPricingTimestamp() external {
        _oracle.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        // Too soon
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(UsingTellor.getDataBefore.selector),
            abi.encode(true, abi.encode(1), block.timestamp)
        );
        vm.expectRevert(TellorOracle.InvalidPricingTimestamp.selector);
        _oracle.getPriceInEth(ETH);

        // Too far in past
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(UsingTellor.getDataBefore.selector),
            abi.encode(true, abi.encode(1), block.timestamp - 1 weeks)
        );
        vm.expectRevert(TellorOracle.InvalidPricingTimestamp.selector);
        _oracle.getPriceInEth(ETH);
    }

    // Testing getting values within smaller timeframe, between 15 minute pricing freshness cut off and 30 min pricing
    //      timeout.
    function test_ReturnPriceWithinSmallerTimeframe() external {
        _oracle.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 20 minutes);

        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(TellorPlayground.getDataBefore.selector),
            abi.encode(true, abi.encodePacked(uint256(1500)), block.timestamp)
        );

        skip(18 minutes);

        uint256 value = _oracle.getPriceInEth(ETH);
        assertEq(value, 1500);
    }

    function test_getPriceInEth_DoesNotReplaceCachedPrice_WithOlderPrice() external {
        // Register ETH - USD pricing feed.  Denomination is Eth, doesn't matter for this scenario.
        _oracle.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        // First `getDataBefore` price, returns price and timestamp price retrieved at.
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(TellorPlayground.getDataBefore.selector),
            abi.encode(true, abi.encodePacked(uint256(1500)), block.timestamp - 30 minutes)
        );

        // Call will cache price from previous mockCall.
        uint256 returnedPrice = _oracle.getPriceInEth(ETH);

        // Check to make sure price cached properly.
        assertEq(returnedPrice, 1500);

        // Return different price at older timestamp on next call.
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(TellorPlayground.getDataBefore.selector),
            abi.encode(true, abi.encodePacked(uint256(1750)), block.timestamp - 45 minutes)
        );

        // Call will not overwrite price from first call, because most recent call to oracle returns an
        //      older timestamp.
        returnedPrice = _oracle.getPriceInEth(ETH);

        // Check that price has not changed.
        assertEq(returnedPrice, 1500);
    }

    function test_getPriceInEth_ReplacesCachedPrice_WithNewerPrice() external {
        // Register ETH - USD pricing feed.  Denomination is Eth, doesn't matter for this scenario.
        _oracle.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        // First `getDataBefore` price, returns price and timestamp price retrieved at.
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(TellorPlayground.getDataBefore.selector),
            abi.encode(true, abi.encodePacked(uint256(1500)), block.timestamp - 30 minutes)
        );

        // Call will cache price from previous mockCall.
        uint256 returnedPrice = _oracle.getPriceInEth(ETH);

        // Check to make sure price cached properly.
        assertEq(returnedPrice, 1500);

        // Return different price at newer timestamp on next call.
        vm.mockCall(
            TELLOR_ORACLE,
            abi.encodeWithSelector(TellorPlayground.getDataBefore.selector),
            abi.encode(true, abi.encodePacked(uint256(1750)), block.timestamp - 20 minutes)
        );

        // Call will overwrite price from first call because timestamp is newer.
        returnedPrice = _oracle.getPriceInEth(ETH);

        // Check that price has changed to newer price.
        assertEq(returnedPrice, 1750);
    }

    function test_GetPriceMainnet() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_100_000);

        TellorOracle mainnet = new TellorOracle(systemRegistry, TELLOR_ORACLE);
        mainnet.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        vm.prank(address(1));
        uint256 returnedPrice = mainnet.getPriceInEth(ETH);

        assertGt(returnedPrice, 0);
        assertLt(returnedPrice, ETH_MAX_USD);
    }

    function test_GetPriceOptimism() external {
        vm.createSelectFork(vm.envString("OPTIMISM_MAINNET_RPC_URL"), 90_000_000);

        TellorOracle optimism = new TellorOracle(systemRegistry, TELLOR_ORACLE);
        optimism.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 0);

        vm.prank(address(1));

        uint256 returnedPrice = optimism.getPriceInEth(ETH);

        assertGt(returnedPrice, 0);
        assertLt(returnedPrice, ETH_MAX_USD);
    }

    function test_GetPriceArbitrum() external {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 80_000_000);

        TellorOracle arbitrum = new TellorOracle(systemRegistry, TELLOR_ORACLE);
        arbitrum.addTellorRegistration(ETH, QUERY_ID, BaseOracleDenominations.Denomination.ETH, 48 hours);

        vm.prank(address(1));

        uint256 returnedPrice = arbitrum.getPriceInEth(ETH);

        assertGt(returnedPrice, 0);
        assertLt(returnedPrice, ETH_MAX_USD);
    }

    function generateSystemRegistry(
        address registry,
        address accessControl,
        address rootOracle
    ) internal returns (ISystemRegistry) {
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));

        vm.mockCall(
            registry, abi.encodeWithSelector(ISystemRegistry.accessController.selector), abi.encode(accessControl)
        );

        return ISystemRegistry(registry);
    }
}
