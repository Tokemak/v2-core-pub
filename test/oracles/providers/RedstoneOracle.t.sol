// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { PRANK_ADDRESS, WEETH_MAINNET, WEETH_RS_FEED_MAINNET } from "test/utils/Addresses.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";

import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract RedstoneOracleTest is Test {
    RedstoneOracle private _oracle;

    error AccessDenied();
    error InvalidDataReturned();

    event OracleRegistrationAdded(address token, address oracle, BaseOracleDenominations.Denomination, uint8 decimals);
    event OracleRegistrationRemoved(address token, address oracle);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_419_462);

        ISystemRegistry registry = ISystemRegistry(address(777));
        AccessController accessControl = new AccessController(address(registry));
        IRootPriceOracle rootPriceOracle = IRootPriceOracle(vm.addr(324));
        generateSystemRegistry(address(registry), address(accessControl), address(rootPriceOracle));
        _oracle = new RedstoneOracle(registry);
    }

    // Test `registerOracle()`
    function test_RevertNonOwner() external {
        vm.prank(PRANK_ADDRESS);
        vm.expectRevert(AccessDenied.selector);

        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_enum() external {
        vm.expectRevert();

        _oracle.registerOracle(
            WEETH_MAINNET,
            IAggregatorV3Interface(WEETH_RS_FEED_MAINNET),
            BaseOracleDenominations.Denomination(uint8(3)),
            0
        );
    }

    function test_RevertZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenToAddOracle"));

        _oracle.registerOracle(
            address(0), IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_RevertZeroAddressOracle() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oracle"));

        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(address(0)), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_RevertOracleAlreadySet() external {
        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, WEETH_MAINNET));

        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_ProperAddOracle() external {
        vm.expectEmit(false, false, false, true);
        emit OracleRegistrationAdded(WEETH_MAINNET, WEETH_RS_FEED_MAINNET, BaseOracleDenominations.Denomination.ETH, 8);

        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        RedstoneOracle.OracleInfo memory clInfo = _oracle.getRedstoneInfo(WEETH_MAINNET);
        assertEq(address(clInfo.oracle), WEETH_RS_FEED_MAINNET);
        assertEq(uint8(clInfo.denomination), uint8(BaseOracleDenominations.Denomination.ETH));
        assertEq(clInfo.decimals, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET).decimals());
        assertEq(clInfo.pricingTimeout, uint16(0));
    }

    // Test `removeRedstoneRegistration()`
    function test_RevertNonOwner_RemoveRegistration() external {
        vm.prank(PRANK_ADDRESS);
        vm.expectRevert(AccessDenied.selector);

        _oracle.removeOracleRegistration(address(1));
    }

    function test_RevertZeroAddressToken() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenToRemoveOracle"));

        _oracle.removeOracleRegistration(address(0));
    }

    function test_RevertOracleNotSet() external {
        vm.expectRevert(Errors.MustBeSet.selector);

        _oracle.removeOracleRegistration(WEETH_MAINNET);
    }

    function test_ProperRemoveOracle() external {
        _oracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        assertEq(address(_oracle.getRedstoneInfo(WEETH_MAINNET).oracle), WEETH_RS_FEED_MAINNET);

        vm.expectEmit(false, false, false, true);
        emit OracleRegistrationRemoved(WEETH_MAINNET, WEETH_RS_FEED_MAINNET);

        _oracle.removeOracleRegistration(WEETH_MAINNET);

        assertEq(address(_oracle.getRedstoneInfo(WEETH_MAINNET).oracle), address(0));
    }

    // Test `getPriceInEth()`
    function test_RevertOracleNotRegistered() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "Oracle"));

        _oracle.getPriceInEth(address(1));
    }

    function test_ReturnsProperPriceRS() external {
        _oracle.registerOracle(
            WEETH_MAINNET,
            IAggregatorV3Interface(WEETH_RS_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        uint256 priceReturned = _oracle.getPriceInEth(WEETH_MAINNET);

        assertGt(priceReturned, 0);
        assertLt(priceReturned, 10_000_000_000_000_000_000);
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
