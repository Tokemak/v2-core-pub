// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { PRANK_ADDRESS, RETH_MAINNET, RETH_CL_FEED_MAINNET } from "test/utils/Addresses.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";

import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract ChainlinkOracleTest is Test {
    IRootPriceOracle private _rootPriceOracle;
    ISystemRegistry private _systemRegistry;
    ChainlinkOracle private _oracle;

    event ChainlinkRegistrationAdded(
        address token, address chainlinkOracle, BaseOracleDenominations.Denomination, uint8 decimals
    );
    event ChainlinkRegistrationRemoved(address token, address chainlinkOracle);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_000_000);

        _rootPriceOracle = IRootPriceOracle(vm.addr(324));
        _systemRegistry = _generateSystemRegistry(address(_rootPriceOracle));
        _oracle = new ChainlinkOracle(_systemRegistry);
    }

    // Test `registerChainlinkOracle()`
    function test_RevertNonOwner() external {
        vm.prank(PRANK_ADDRESS);
        vm.expectRevert("Ownable: caller is not the owner");

        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_RevertZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenToAddOracle"));

        _oracle.registerChainlinkOracle(
            address(0), IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_RevertZeroAddressOracle() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oracle"));

        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(address(0)), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_RevertOracleAlreadySet() external {
        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        vm.expectRevert(Errors.MustBeZero.selector);

        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_ProperAddOracle() external {
        vm.expectEmit(false, false, false, true);
        emit ChainlinkRegistrationAdded(
            RETH_MAINNET, RETH_CL_FEED_MAINNET, BaseOracleDenominations.Denomination.ETH, 18
        );

        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        ChainlinkOracle.ChainlinkInfo memory clInfo = _oracle.getChainlinkInfo(RETH_MAINNET);
        assertEq(address(clInfo.oracle), RETH_CL_FEED_MAINNET);
        assertEq(uint8(clInfo.denomination), uint8(BaseOracleDenominations.Denomination.ETH));
        assertEq(clInfo.decimals, IAggregatorV3Interface(RETH_CL_FEED_MAINNET).decimals());
        assertEq(clInfo.pricingTimeout, uint16(0));
    }

    // Test `removeChainlinkRegistration()`
    function test_RevertZeroAddressToken() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenToRemoveOracle"));

        _oracle.removeChainlinkRegistration(address(0));
    }

    function test_RevertOracleNotSet() external {
        vm.expectRevert(Errors.MustBeSet.selector);

        _oracle.removeChainlinkRegistration(RETH_MAINNET);
    }

    function test_ProperRemoveOracle() external {
        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        assertEq(address(_oracle.getChainlinkInfo(RETH_MAINNET).oracle), RETH_CL_FEED_MAINNET);

        vm.expectEmit(false, false, false, true);
        emit ChainlinkRegistrationRemoved(RETH_MAINNET, RETH_CL_FEED_MAINNET);

        _oracle.removeChainlinkRegistration(RETH_MAINNET);

        assertEq(address(_oracle.getChainlinkInfo(RETH_MAINNET).oracle), address(0));
    }

    // Test `getPriceInEth()`
    function test_RevertOracleNotRegistered() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "chainlinkOracle"));

        _oracle.getPriceInEth(address(1));
    }

    function test_ReturnsProperPrice() external {
        _oracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        uint256 priceReturned = _oracle.getPriceInEth(RETH_MAINNET);
        assertGt(priceReturned, 0);
        assertLt(priceReturned, 10_000_000_000_000_000_000);
    }

    function _generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}
