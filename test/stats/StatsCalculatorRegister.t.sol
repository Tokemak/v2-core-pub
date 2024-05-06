// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IAccessControl } from "openzeppelin-contracts/access/IAccessControl.sol";

import { Roles } from "src/libs/Roles.sol";

contract StatsCalculatorRegistryTests is Test {
    uint256 private addressCounter = 0;
    address private testUser1;

    ISystemRegistry private systemRegistry;
    IAccessController private accessController;
    address private statsFactory;
    StatsCalculatorRegistry private statsRegistry;

    event FactorySet(address newFactory);
    event StatCalculatorRegistered(bytes32 aprId, address calculatorAddress, address caller);

    function setUp() public {
        testUser1 = vm.addr(1);

        systemRegistry = ISystemRegistry(vm.addr(5));
        accessController = IAccessController(vm.addr(6));
        statsFactory = generateFactory(systemRegistry);

        setupInitialSystemRegistry(address(systemRegistry), address(accessController));
        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        ensureOwnerRole();
        statsRegistry.setCalculatorFactory(address(statsFactory));
        setupSystemRegistryWithRegistry(address(systemRegistry), address(statsRegistry));
    }

    function testConstruction() public {
        address sr = statsRegistry.getSystemRegistry();

        assertEq(sr, address(systemRegistry));
    }

    function testOnlyFactoryCanRegister() public {
        bytes32 aprId = keccak256("x");
        address calculator = generateCalculator(aprId);

        // Run as not an owner and ensure it reverts
        vm.startPrank(testUser1);
        vm.expectRevert(abi.encodeWithSelector(StatsCalculatorRegistry.OnlyFactory.selector));
        statsRegistry.register(calculator);
        vm.stopPrank();

        // Run as an owner and ensure it doesn't revert
        vm.startPrank(statsFactory);
        statsRegistry.register(calculator);
        vm.stopPrank();
    }

    function testCalculatorCanOnlyBeRegisteredOnce() public {
        bytes32 aprId = keccak256("x");
        address calculator = generateCalculator(aprId);

        vm.startPrank(statsFactory);
        statsRegistry.register(calculator);
        vm.expectRevert(abi.encodeWithSelector(StatsCalculatorRegistry.AlreadyRegistered.selector, aprId, calculator));
        statsRegistry.register(calculator);
        vm.stopPrank();
    }

    function testZeroAddressCalcCantBeRegistered() public {
        vm.startPrank(statsFactory);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "calculator"));
        statsRegistry.register(address(0));
        vm.stopPrank();
    }

    function testEmptyIdCalcCantBeRegistered() public {
        bytes32 aprId = 0x00;
        address calculator = generateCalculator(aprId);

        vm.startPrank(statsFactory);
        vm.expectRevert();
        statsRegistry.register(calculator);
        vm.stopPrank();
    }

    function testCalcRegistrationEmitsEvent() public {
        bytes32 aprId = keccak256("x");
        address calculator = generateCalculator(aprId);

        vm.startPrank(statsFactory);

        vm.expectEmit(true, true, true, true);
        emit StatCalculatorRegistered(aprId, calculator, statsFactory);
        statsRegistry.register(calculator);
        vm.stopPrank();
    }

    function testCalcCorrectlyRegistersGet() public {
        bytes32 aprId = keccak256("x");
        address calculator = generateCalculator(aprId);
        vm.startPrank(statsFactory);
        statsRegistry.register(calculator);
        vm.stopPrank();

        IStatsCalculator queried = statsRegistry.getCalculator(aprId);
        assertEq(address(queried), calculator);
    }

    function testGetCalcRevertsOnEmpty() public {
        bytes32 aprId = keccak256("x");

        vm.expectRevert();
        statsRegistry.getCalculator(aprId);
    }

    function testOnlyOwnerCanSetFactory() public {
        vm.startPrank(statsFactory);
        address newFactory = generateFactory(ISystemRegistry(vm.addr(2_455_245)));
        vm.expectRevert();
        statsRegistry.setCalculatorFactory(newFactory);
        vm.stopPrank();
    }

    function testFactoryCantBeSetToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "factory"));
        statsRegistry.setCalculatorFactory(address(0));
    }

    function testSetFactoryEmitsEvent() public {
        address newFactory = generateFactory(systemRegistry);
        vm.expectEmit(true, true, true, true);
        emit FactorySet(newFactory);
        statsRegistry.setCalculatorFactory(newFactory);
    }

    function testSetFactoryValidatesSystemMatch() public {
        ISystemRegistry newRegistry = ISystemRegistry(vm.addr(34_343));
        address newFactory = generateFactory(newRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SystemMismatch.selector, address(statsRegistry), address(newFactory))
        );
        statsRegistry.setCalculatorFactory(newFactory);
    }

    function generateCalculator(bytes32 aprId) internal returns (address) {
        addressCounter++;
        address calculator = vm.addr(453 + addressCounter);
        vm.mockCall(calculator, abi.encodeWithSelector(IStatsCalculator.getAprId.selector), abi.encode(aprId));
        return calculator;
    }

    function generateFactory(ISystemRegistry sysRegistry) internal returns (address) {
        address f = vm.addr(7);
        vm.mockCall(f, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(sysRegistry));
        return f;
    }

    function ensureOwnerRole() internal {
        vm.mockCall(
            address(accessController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, Roles.STATS_CALC_REGISTRY_MANAGER, address(this)),
            abi.encode(true)
        );
    }

    function setupInitialSystemRegistry(address _systemRegistry, address accessControl) internal {
        vm.mockCall(
            _systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.accessController.selector),
            abi.encode(accessControl)
        );
    }

    function setupSystemRegistryWithRegistry(address _systemRegistry, address _statsRegistry) internal {
        vm.mockCall(
            _systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.statsCalculatorRegistry.selector),
            abi.encode(_statsRegistry)
        );
    }
}
