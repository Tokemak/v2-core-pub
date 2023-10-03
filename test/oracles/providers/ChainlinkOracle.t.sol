// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { PRANK_ADDRESS, RETH_MAINNET, RETH_CL_FEED_MAINNET } from "test/utils/Addresses.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";

import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract ChainlinkOracleTest is Test {
    ChainlinkOracle private _oracle;

    error AccessDenied();
    error InvalidDataReturned();

    event ChainlinkRegistrationAdded(
        address token, address chainlinkOracle, BaseOracleDenominations.Denomination, uint8 decimals
    );
    event ChainlinkRegistrationRemoved(address token, address chainlinkOracle);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_000_000);

        ISystemRegistry registry = ISystemRegistry(address(777));
        AccessController accessControl = new AccessController(address(registry));
        IRootPriceOracle rootPriceOracle = IRootPriceOracle(vm.addr(324));
        generateSystemRegistry(address(registry), address(accessControl), address(rootPriceOracle));
        _oracle = new ChainlinkOracle(registry);
    }

    // Test `registerChainlinkOracle()`
    function test_RevertNonOwner() external {
        vm.prank(PRANK_ADDRESS);
        vm.expectRevert(AccessDenied.selector);

        _oracle.registerChainlinkOracle(
            RETH_MAINNET, IAggregatorV3Interface(RETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );
    }

    function test_enum() external {
        vm.expectRevert();

        _oracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination(uint8(3)),
            0
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
    function test_RevertNonOwner_RemoveRegistration() external {
        vm.prank(PRANK_ADDRESS);
        vm.expectRevert(AccessDenied.selector);

        _oracle.removeChainlinkRegistration(address(1));
    }

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

    function test_OracleRevertsMinPrice() external {
        _oracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            52 weeks
        );

        // roundId = 1.
        // answer = 1, minPrice for rEth feed.
        // startedAt = 1680840010, timestamp a few hours before forked block.
        // updatedAt = 1680840010, same as above line.
        // answeredInRound = 1.
        vm.mockCall(
            RETH_CL_FEED_MAINNET,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 1, 1_680_840_010, 1_680_840_010, 1)
        );

        vm.expectRevert(InvalidDataReturned.selector);
        _oracle.getPriceInEth(RETH_MAINNET);
    }

    function test_OracleRevertsMaxPrice() external {
        _oracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            52 weeks
        );

        // roundId = 1.
        // answer = 95780971304118053647396689196894323976171195136475135, maxPrice for rEth feed.
        // startedAt = 1680840010, timestamp a few hours before forked block.
        // updatedAt = 1680840010, same as above line.
        // answeredInRound = 1.
        vm.mockCall(
            RETH_CL_FEED_MAINNET,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(
                1,
                95_780_971_304_118_053_647_396_689_196_894_323_976_171_195_136_475_135,
                1_680_840_010,
                1_680_840_010,
                1
            )
        );

        vm.expectRevert(InvalidDataReturned.selector);
        _oracle.getPriceInEth(RETH_MAINNET);
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
