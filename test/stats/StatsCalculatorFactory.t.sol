// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { IAccessControl } from "openzeppelin-contracts/access/IAccessControl.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";

contract StatsCalculatorFactoryTests is Test {
    address private testUser1;

    ISystemRegistry private systemRegistry;
    IAccessController private accessController;
    IStatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private factory;

    event TemplateRemoved(bytes32 aprTemplateId, address template);
    event TemplateReplaced(bytes32 aprTemplateId, address oldAddress, address newAddress);
    event TemplateRegistered(bytes32 aprTemplateId, address newTemplate);

    function setUp() public {
        testUser1 = vm.addr(1);

        systemRegistry = ISystemRegistry(vm.addr(5));
        accessController = IAccessController(vm.addr(6));
        statsRegistry = IStatsCalculatorRegistry(vm.addr(7));

        setupSystemRegistry(address(systemRegistry), address(accessController), address(statsRegistry));
        factory = new StatsCalculatorFactory(systemRegistry);
    }

    function testConstruction() public {
        address sr = factory.getSystemRegistry();

        assertEq(sr, address(systemRegistry));
    }

    function testRegisterTemplateRevertsIfSystemMismatch() public {
        address fakeRegistry = makeAddr("FAKE_SYSTEM_REGISTRY");
        address template = vm.addr(1001);
        bytes32 aprTemplateId = keccak256("CurveConvex1");

        ensureTemplateManagerRole();
        vm.mockCall(template, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(fakeRegistry));

        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(systemRegistry), fakeRegistry));
        factory.registerTemplate(aprTemplateId, template);
    }

    function testRegisteringTemplate() public {
        address template = vm.addr(1001);
        bytes32 aprTemplateId = keccak256("CurveConvex1");
        ensureTemplateManagerRole();

        vm.expectEmit(true, true, true, true);
        emit TemplateRegistered(aprTemplateId, template);
        factory.registerTemplate(aprTemplateId, template);

        address queriedTemplate = factory.templates(aprTemplateId);
        assertEq(queriedTemplate, template);
    }

    function testRegisterTemplateValidId() public { }

    function testRegisterTemplateValidAddress() public { }

    function testRegisterTemplateCanReplace() public { }

    function testRegisterTemplateChecksRole() public { }

    function testRemovingTemplate() public {
        address template = vm.addr(1001);
        bytes32 aprTemplateId = keccak256("CurveConvex1");
        ensureTemplateManagerRole();

        factory.registerTemplate(aprTemplateId, template);

        vm.expectEmit(true, true, true, true);
        emit TemplateRemoved(aprTemplateId, template);

        factory.removeTemplate(aprTemplateId);

        address queriedTemplate = factory.templates(aprTemplateId);
        assertEq(queriedTemplate, address(0));
    }

    function testRemoveTemplateValidId() public { }

    function testRemoveTemplateMustBeRegistered() public { }

    function testRemoveTemplateChecksRole() public { }

    function testReplaceTemplateRevertsIfSystemMismatch() public {
        address fakeRegistry = makeAddr("FAKE_SYSTEM_REGISTRY");
        address template = vm.addr(1001);
        address templateNew = vm.addr(1002);
        bytes32 aprTemplateId = keccak256("CurveConvex1");
        ensureTemplateManagerRole();

        vm.mockCall(template, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(address(systemRegistry)));
        factory.registerTemplate(aprTemplateId, template);

        vm.mockCall(templateNew, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(fakeRegistry));

        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(systemRegistry), fakeRegistry));
        factory.replaceTemplate(aprTemplateId, template, templateNew);
    }

    function testReplacingTemplate() public {
        address template = vm.addr(1001);
        address templateNew = vm.addr(1002);
        bytes32 aprTemplateId = keccak256("CurveConvex1");
        ensureTemplateManagerRole();

        factory.registerTemplate(aprTemplateId, template);

        vm.expectEmit(true, true, true, true);
        emit TemplateReplaced(aprTemplateId, template, templateNew);
        factory.replaceTemplate(aprTemplateId, template, templateNew);

        address queriedTemplate = factory.templates(aprTemplateId);
        assertEq(queriedTemplate, templateNew);
    }

    function testReplaceTemplateValidId() public { }

    function testReplaceTemplateValidAddresses() public { }

    function testReplaceTemplateEnsureOldMatch() public { }

    function testReplaceTemplateNewOldDontMatch() public { }

    function testReplaceTemplateChecksRole() public { }

    function testBasicCreate() public {
        TestCalculator template = new TestCalculator(systemRegistry);
        bytes32 aprTemplateId = keccak256("CurveConvex1");
        ensureTemplateManagerRole();
        ensureCalcCreatorRole();

        factory.registerTemplate(aprTemplateId, address(template));

        address poolAddress = vm.addr(2000);
        address stakingAddress = vm.addr(2001);
        uint256 initBaseApr = 9;
        TestCalculator.InitData memory initData = TestCalculator.InitData({
            poolAddress: poolAddress,
            stakingAddress: stakingAddress,
            initBaseApr: initBaseApr
        });
        bytes memory encodedInitData = abi.encode(initData);

        // Ensure Initialize is called with data and registry
        // Ensure values are registered in the stats calc registry
        ensureRegisterPasses();
        bytes32 expectedAprId = keccak256(abi.encode("tokeDexV1", poolAddress, stakingAddress));
        address expectedCalculatorAddress = computeCreateAddress(address(factory), 1);
        vm.expectCall(
            address(statsRegistry), abi.encodeCall(IStatsCalculatorRegistry.register, (expectedCalculatorAddress))
        );
        bytes32[] memory e = new bytes32[](0);
        (address calculatorAddress) = factory.create(aprTemplateId, e, encodedInitData);
        TestCalculator createdCalc = TestCalculator(calculatorAddress);
        bytes32 aprId = createdCalc.getAprId();

        assertEq(expectedAprId, aprId);
        assertEq(address(createdCalc.systemRegistry()), address(systemRegistry));
    }

    function testCreateChecksRole() public { }

    function testCreateRequiresRegisteredTemplate() public { }

    function testCreateReturnsAprId() public { }

    function ensureRegisterPasses() internal {
        vm.mockCall(
            address(statsRegistry), abi.encodeWithSelector(IStatsCalculatorRegistry.register.selector), abi.encode("")
        );
    }

    function ensureTemplateManagerRole() internal {
        vm.mockCall(
            address(accessController),
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, address(this)
            ),
            abi.encode(true)
        );
    }

    function ensureCalcCreatorRole() internal {
        vm.mockCall(
            address(accessController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, Roles.STATS_CALC_FACTORY_MANAGER, address(this)),
            abi.encode(true)
        );
    }

    function setupSystemRegistry(address _systemRegistry, address accessControl, address _statsRegistry) internal {
        vm.mockCall(
            _systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.statsCalculatorRegistry.selector),
            abi.encode(_statsRegistry)
        );
        vm.mockCall(
            _systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.accessController.selector),
            abi.encode(accessControl)
        );
    }
}

contract TestCalculator is IStatsCalculator {
    string public constant BASE_APR_ID_KEY = "tokeDexV1";

    bytes32 private aprId;

    ISystemRegistry public immutable systemRegistry;

    struct InitData {
        address poolAddress;
        address stakingAddress;
        uint256 initBaseApr;
    }

    constructor(ISystemRegistry _systemRegistry) {
        systemRegistry = _systemRegistry;
    }

    function getAddressId() external pure returns (address) {
        return address(0);
    }

    function getAprId() external view returns (bytes32) {
        return aprId;
    }

    function initialize(bytes32[] calldata, bytes calldata initData) external {
        InitData memory init = abi.decode(initData, (InitData));
        aprId = keccak256(abi.encode(BASE_APR_ID_KEY, init.poolAddress, init.stakingAddress));
    }

    function snapshot() external { }

    function shouldSnapshot() external pure returns (bool takeSnapshot) {
        return true;
    }
}
