// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { MaverickFeeAprOracle } from "src/oracles/providers/MaverickFeeAprOracle.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { Errors } from "src/utils/Errors.sol";

import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";

import { Roles } from "src/libs/Roles.sol";

// solhint-disable func-name-mixedcase
contract MaverickFeeAprOracleTest is Test {
    MaverickFeeAprOracle internal oracle;

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RootPriceOracle private rootPriceOracle;

    address internal boostedPosition0 = vm.addr(111);
    address internal boostedPosition1 = vm.addr(222);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_579_296);
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.MAVERICK_FEE_ORACLE_EXECUTOR, address(this));
        accessController.grantRole(Roles.ORACLE_MANAGER, address(this));
        accessController.grantRole(Roles.STATS_CALC_REGISTRY_MANAGER, address(this));

        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        oracle = new MaverickFeeAprOracle(systemRegistry);
    }
}

contract SetFeeApr is MaverickFeeAprOracleTest {
    function test_SetFeeApr() public {
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);
        uint256 feeApr0 = oracle.getFeeApr(boostedPosition0);
        assertEq(feeApr0, 100);

        oracle.setFeeApr(boostedPosition1, 200, block.timestamp - 100);
        uint256 feeApr1 = oracle.getFeeApr(boostedPosition1);
        assertEq(feeApr1, 200);
    }

    function test_RevertIfUnauthorized() public {
        vm.prank(makeAddr("fake"));
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);
    }

    function test_RevertIfFeeAprQueriedTimestampInTheFuture() public {
        vm.expectRevert();
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp + 1);
    }

    function test_RevertIfFeeAprToHigh() public {
        vm.expectRevert();
        oracle.setFeeApr(boostedPosition0, 300e50, block.timestamp);
    }

    function test_RevertIfCallerDoesNotHaveRole() public {
        vm.prank(vm.addr(333));
        vm.expectRevert();
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);
    }

    function test_RevertIfWritingOlderValue() public {
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);
        vm.expectRevert();
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp - 1);
    }
}

contract GetFeeApr is MaverickFeeAprOracleTest {
    function test_RevertIfFeeAprNotSet() public {
        vm.expectRevert();
        oracle.getFeeApr(boostedPosition0);
    }

    function test_RevertIfFeeAprExpired() public {
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);
        oracle.getFeeApr(boostedPosition0);

        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert();
        oracle.getFeeApr(boostedPosition0);
    }

    function test_RevertIfFeeAprExpiredNewFeeAprLatency() public {
        oracle.setFeeApr(boostedPosition0, 100, block.timestamp);

        oracle.setMaxFeeAprLatency(3 days);
        vm.warp(block.timestamp + 3 days);
        oracle.getFeeApr(boostedPosition0);
        vm.warp(block.timestamp + 1);

        vm.expectRevert();
        oracle.getFeeApr(boostedPosition0);
    }
}

contract SetMaxFeeAprLatency is MaverickFeeAprOracleTest {
    function test_RevertIfUnauthorized() public {
        vm.prank(makeAddr("fake"));
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        oracle.setMaxFeeAprLatency(uint256(type(uint32).max));
    }

    function test_SetMaxFeeAprLatency() public {
        uint256 val = uint256(type(uint32).max);
        oracle.setMaxFeeAprLatency(val);

        assertEq(oracle.maxFeeAprLatency(), val);
    }

    function test_RevertIfMaxFeeAprLatencyTooHigh() public {
        oracle.setMaxFeeAprLatency(uint256(type(uint32).max));
        vm.expectRevert();
        oracle.setMaxFeeAprLatency(uint256(type(uint32).max) + 1);
    }

    function test_RevertIfCallerDoesNotHaveRole() public {
        vm.prank(vm.addr(333));
        vm.expectRevert();
        oracle.setMaxFeeAprLatency(uint256(type(uint32).max));
    }
}
