// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Errors } from "src/utils/Errors.sol";
import { Test } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { SystemRegistryBase } from "src/SystemRegistryBase.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";

// solhint-disable func-name-mixedcase

contract SystemRegistryTest is Test {
    SystemRegistry private _systemRegistry;

    event AutopoolRegistrySet(address newAddress);
    event AccessControllerSet(address newAddress);
    event StatsCalculatorRegistrySet(address newAddress);
    event DestinationVaultRegistrySet(address newAddress);
    event DestinationTemplateRegistrySet(address newAddress);
    event RootPriceOracleSet(address rootPriceOracle);
    event SwapRouterSet(address swapRouter);
    event CurveResolverSet(address curveResolver);
    event SystemSecuritySet(address security);
    event AutopilotRouterSet(address router);
    event AutopoolFactorySet(bytes32 vaultType, address factory);
    event IncentivePricingStatsSet(address incentivePricingStats);
    event MessageProxySet(address messageProxy);
    event ReceivingRouterSet(address recevingRouter);
    event ContractSet(bytes32 contractType, address contractAddress);
    event ContractUnset(bytes32 contractType, address contractAddress);
    event UniqueContractSet(bytes32 contractType, address contractAddress);
    event UniqueContractUnset(bytes32 contractType);

    function setUp() public {
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
    }

    /* ******************************** */
    /* Autopool Vault Registry
    /* ******************************** */

    function testSystemRegistryAutopoolETHSetDuplicateValue() public {
        address autoPool = vm.addr(1);
        mockSystemComponent(autoPool);
        _systemRegistry.setAutopoolRegistry(autoPool);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, autoPool));
        _systemRegistry.setAutopoolRegistry(autoPool);
    }

    function testSystemRegistryAutopoolETHSetDifferentValue() public {
        address autoPool = vm.addr(1);
        mockSystemComponent(autoPool);
        _systemRegistry.setAutopoolRegistry(autoPool);
        autoPool = vm.addr(2);
        mockSystemComponent(autoPool);
        _systemRegistry.setAutopoolRegistry(autoPool);
    }

    function testSystemRegistryAutopoolETHZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "autoPoolRegistry"));
        _systemRegistry.setAutopoolRegistry(address(0));
    }

    function testSystemRegistryAutopoolETHRetrieveSetValue() public {
        address autoPool = vm.addr(3);
        mockSystemComponent(autoPool);
        _systemRegistry.setAutopoolRegistry(autoPool);
        IAutopoolRegistry queried = _systemRegistry.autoPoolRegistry();

        assertEq(autoPool, address(queried));
    }

    function testSystemRegistryAutopoolETHEmitsEventWithNewAddress() public {
        address autoPool = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit AutopoolRegistrySet(autoPool);

        mockSystemComponent(autoPool);
        _systemRegistry.setAutopoolRegistry(autoPool);
    }

    function testSystemRegistryAutopoolETHOnlyCallableByOwner() public {
        address autoPool = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setAutopoolRegistry(autoPool);
    }

    function testSystemRegistryAutopoolETHSystemsMatch() public {
        address autoPool = vm.addr(1);
        address fakeRegistry = vm.addr(2);
        bytes memory registry = abi.encode(fakeRegistry);
        vm.mockCall(autoPool, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), registry);
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setAutopoolRegistry(autoPool);
    }

    function testSystemRegistryAutopoolETHInvalidContractCaught() public {
        // When its not a contract
        address fakeRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setAutopoolRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setAutopoolRegistry(emptyContract);
    }

    /* ******************************** */
    /* Autopool Vault Router
    /* ******************************** */

    function test_OnlyOwner_setAutopilotRouter() external {
        address fakeOwner = vm.addr(3);
        address fakeAutopoolRouter = vm.addr(4);

        vm.prank(fakeOwner);
        vm.expectRevert("Ownable: caller is not the owner");

        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);
    }

    function test_ZeroAddress_setAutopilotRouter() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "autoPoolRouter"));
        _systemRegistry.setAutopilotRouter(address(0));
    }

    function test_Duplicate_setAutopilotRouter() external {
        address fakeAutopoolRouter = vm.addr(4);
        mockSystemComponent(fakeAutopoolRouter);

        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, fakeAutopoolRouter));
        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);
    }

    function test_WorksProperly_setAutopilotRouter() external {
        address fakeAutopoolRouter = vm.addr(4);
        mockSystemComponent(fakeAutopoolRouter);

        vm.expectEmit(false, false, false, true);
        emit AutopilotRouterSet(fakeAutopoolRouter);
        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);

        assertEq(fakeAutopoolRouter, address(_systemRegistry.autoPoolRouter()));
    }

    function test_SetMultipleTimes_setAutopilotRouter() external {
        address fakeAutopoolRouter1 = vm.addr(4);
        address fakeAutopoolRouter2 = vm.addr(5);

        mockSystemComponent(fakeAutopoolRouter1);
        mockSystemComponent(fakeAutopoolRouter2);

        // First set
        vm.expectEmit(false, false, false, true);
        emit AutopilotRouterSet(fakeAutopoolRouter1);
        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter1);
        assertEq(fakeAutopoolRouter1, address(_systemRegistry.autoPoolRouter()));

        // Second set
        vm.expectEmit(false, false, false, true);
        emit AutopilotRouterSet(fakeAutopoolRouter2);
        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter2);
        assertEq(fakeAutopoolRouter2, address(_systemRegistry.autoPoolRouter()));
    }

    function test_SystemMismatch_setAutopilotRouter() external {
        address fakeAutopoolRouter = vm.addr(4);
        address fakeRegistry = vm.addr(3);

        vm.mockCall(
            fakeAutopoolRouter,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));

        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);
    }

    function test_InvalidContract_setAutopilotRouter() external {
        address fakeAutopoolRouter = vm.addr(4);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeAutopoolRouter));
        _systemRegistry.setAutopilotRouter(fakeAutopoolRouter);

        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setAutopilotRouter(emptyContract);
    }

    /* ******************************** */
    /* Destination Vault Registry
    /* ******************************** */

    function testSystemRegistryDestinationVaultSetDuplicateValue() public {
        address destinationVault = vm.addr(1);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, destinationVault));
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultSetOnceDifferentValue() public {
        address destinationVault = vm.addr(1);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
        destinationVault = vm.addr(2);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "destinationVaultRegistry"));
        _systemRegistry.setDestinationVaultRegistry(address(0));
    }

    function testSystemRegistryDestinationVaultRetrieveSetValue() public {
        address destinationVault = vm.addr(3);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
        IDestinationVaultRegistry queried = _systemRegistry.destinationVaultRegistry();

        assertEq(destinationVault, address(queried));
    }

    function testSystemRegistryDestinationVaultEmitsEventWithNewAddress() public {
        address destinationVault = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit DestinationVaultRegistrySet(destinationVault);

        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultOnlyCallableByOwner() public {
        address destinationVault = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultSystemsMatch() public {
        address destinationVault = vm.addr(1);
        address fakeRegistry = vm.addr(2);
        vm.mockCall(
            destinationVault,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultInvalidContractCaught() public {
        // When its not a contract
        address fakeRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setDestinationVaultRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setDestinationVaultRegistry(emptyContract);
    }

    /* ******************************** */
    /* Destination Template Registry
    /* ******************************** */

    function testSystemRegistryDestinationTemplateSetDuplicateValue() public {
        address destinationTemplate = vm.addr(1);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, destinationTemplate));
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateSetDifferentValue() public {
        address destinationTemplate = vm.addr(1);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
        destinationTemplate = vm.addr(2);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "destinationTemplateRegistry"));
        _systemRegistry.setDestinationTemplateRegistry(address(0));
    }

    function testSystemRegistryDestinationTemplateRetrieveSetValue() public {
        address destinationTemplate = vm.addr(3);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
        IDestinationRegistry queried = _systemRegistry.destinationTemplateRegistry();

        assertEq(destinationTemplate, address(queried));
    }

    function testSystemRegistryDestinationTemplateEmitsEventWithNewAddress() public {
        address destinationTemplate = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit DestinationTemplateRegistrySet(destinationTemplate);

        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateOnlyCallableByOwner() public {
        address destinationTemplate = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateSystemsMatch() public {
        address destinationTemplate = vm.addr(1);
        address fakeRegistry = vm.addr(2);
        vm.mockCall(
            destinationTemplate,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateInvalidContractCaught() public {
        // When its not a contract
        address fakeRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setDestinationTemplateRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setDestinationTemplateRegistry(emptyContract);
    }

    /* ******************************** */
    /* Access Controller
    /* ******************************** */

    function testSystemRegistryAccessControllerVaultSetOnceDuplicateValue() public {
        address accessController = vm.addr(1);
        mockSystemComponent(accessController);
        _systemRegistry.setAccessController(accessController);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "accessController"));
        _systemRegistry.setAccessController(accessController);
    }

    function testSystemRegistryAccessControllerVaultSetOnceDifferentValue() public {
        address accessController = vm.addr(1);
        mockSystemComponent(accessController);
        _systemRegistry.setAccessController(accessController);
        accessController = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "accessController"));
        _systemRegistry.setAccessController(accessController);
    }

    function testSystemRegistryAccessControllerVaultZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "accessController"));
        _systemRegistry.setAccessController(address(0));
    }

    function testSystemRegistryAccessControllerVaultRetrieveSetValue() public {
        address accessController = vm.addr(3);
        mockSystemComponent(accessController);
        _systemRegistry.setAccessController(accessController);
        IAccessController queried = _systemRegistry.accessController();

        assertEq(accessController, address(queried));
    }

    function testSystemRegistryAccessControllerEmitsEventWithNewAddress() public {
        address accessController = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit AccessControllerSet(accessController);

        mockSystemComponent(accessController);
        _systemRegistry.setAccessController(accessController);
    }

    function testSystemRegistryAccessControllerOnlyCallableByOwner() public {
        address accessController = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setAccessController(accessController);
    }

    function testSystemRegistryAccessControllerSystemsMatch() public {
        address controller = vm.addr(1);
        address fakeController = vm.addr(2);
        vm.mockCall(
            controller, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fakeController)
        );
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeController)
        );
        _systemRegistry.setAccessController(controller);
    }

    function testSystemRegistryAccessControllerInvalidContractCaught() public {
        // When its not a contract
        address fakeController = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeController));
        _systemRegistry.setAccessController(fakeController);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setAccessController(emptyContract);
    }

    /* ******************************** */
    /* Stats Calc Registry
    /* ******************************** */

    function testSystemRegistryStatsCalcRegistrySetDuplicateValue() public {
        address statsCalcRegistry = vm.addr(1);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, statsCalcRegistry));
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistrySetOnceDifferentValue() public {
        address statsCalcRegistry = vm.addr(1);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
        statsCalcRegistry = vm.addr(2);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistryZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "statsCalculatorRegistry"));
        _systemRegistry.setStatsCalculatorRegistry(address(0));
    }

    function testSystemRegistryStatsCalcRegistryRetrieveSetValue() public {
        address statsCalcRegistry = vm.addr(3);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
        IStatsCalculatorRegistry queried = _systemRegistry.statsCalculatorRegistry();

        assertEq(statsCalcRegistry, address(queried));
    }

    function testSystemRegistryStatsCalcRegistryEmitsEventWithNewAddress() public {
        address statsCalcRegistry = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit StatsCalculatorRegistrySet(statsCalcRegistry);

        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistryOnlyCallableByOwner() public {
        address statsCalcRegistry = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistrySystemsMatch() public {
        address statsCalcRegistry = vm.addr(1);
        address fakeStatsCalcRegistry = vm.addr(2);
        vm.mockCall(
            statsCalcRegistry,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeStatsCalcRegistry)
        );
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeStatsCalcRegistry)
        );
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistryInvalidContractCaught() public {
        // When its not a contract
        address fakeStatsCalcRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeStatsCalcRegistry));
        _systemRegistry.setStatsCalculatorRegistry(fakeStatsCalcRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setStatsCalculatorRegistry(emptyContract);
    }

    /* ******************************** */
    /* Root Price Oracle
    /* ******************************** */

    function testSystemRegistryRootPriceOracleCanSetMultipleTimes() public {
        address oracle = vm.addr(1);
        mockSystemComponent(oracle);
        _systemRegistry.setRootPriceOracle(oracle);
        assertEq(address(_systemRegistry.rootPriceOracle()), oracle);

        address oracle2 = vm.addr(2);
        mockSystemComponent(oracle2);
        _systemRegistry.setRootPriceOracle(oracle2);
        assertEq(address(_systemRegistry.rootPriceOracle()), oracle2);
    }

    function testSystemRegistryRootPriceOracleCantSetDup() public {
        address oracle = vm.addr(1);
        mockSystemComponent(oracle);
        _systemRegistry.setRootPriceOracle(oracle);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(oracle)));
        _systemRegistry.setRootPriceOracle(oracle);
    }

    function testSystemRegistryRootPriceOracleEmitsEventWithNewAddress() public {
        address oracle = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit RootPriceOracleSet(oracle);

        mockSystemComponent(oracle);
        _systemRegistry.setRootPriceOracle(oracle);
    }

    function testSystemRegistryRootPriceOracleOnlyCallableByOwner() public {
        address oracle = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setRootPriceOracle(oracle);
    }

    function testSystemRegistryRootPriceOracleSystemsMatch() public {
        address oracle = vm.addr(1);
        address fake = vm.addr(2);
        vm.mockCall(oracle, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fake));
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fake));
        _systemRegistry.setRootPriceOracle(oracle);
    }

    function testSystemRegistryRootPriceOracleInvalidContractCaught() public {
        // When its not a contract
        address fakeOracle = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeOracle));
        _systemRegistry.setRootPriceOracle(fakeOracle);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setRootPriceOracle(emptyContract);
    }

    /* ******************************** */
    /* Incentive Pricing Stats
    /* ******************************** */

    function testSystemRegistryIncentivePricingCanSetMultipleTimes() public {
        address incentivePricing = vm.addr(1);
        mockSystemComponent(incentivePricing);
        _systemRegistry.setIncentivePricingStats(incentivePricing);
        assertEq(address(_systemRegistry.incentivePricing()), incentivePricing);

        address incentivePricing2 = vm.addr(2);
        mockSystemComponent(incentivePricing2);
        _systemRegistry.setIncentivePricingStats(incentivePricing2);
        assertEq(address(_systemRegistry.incentivePricing()), incentivePricing2);
    }

    function testSystemRegistryIncentivePricingCantSetDup() public {
        address incentivePricing = vm.addr(1);
        mockSystemComponent(incentivePricing);
        _systemRegistry.setIncentivePricingStats(incentivePricing);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(incentivePricing)));
        _systemRegistry.setIncentivePricingStats(incentivePricing);
    }

    function testSystemRegistryIncentivePricingEmitsEventWithNewAddress() public {
        address incentivePricing = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit IncentivePricingStatsSet(incentivePricing);

        mockSystemComponent(incentivePricing);
        _systemRegistry.setIncentivePricingStats(incentivePricing);
    }

    function testSystemRegistryIncentivePricingOnlyCallableByOwner() public {
        address incentivePricing = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setIncentivePricingStats(incentivePricing);
    }

    function testSystemRegistryIncentivePricingSystemsMatch() public {
        address incentivePricing = vm.addr(1);
        address fake = vm.addr(2);
        vm.mockCall(
            incentivePricing, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fake)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fake));
        _systemRegistry.setIncentivePricingStats(incentivePricing);
    }

    function testSystemRegistryIncentivePricingInvalidContractCaught() public {
        // When its not a contract
        address fakeOracle = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeOracle));
        _systemRegistry.setIncentivePricingStats(fakeOracle);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setIncentivePricingStats(emptyContract);
    }
    /* ******************************** */
    /* Reward Token Registry
    /* ******************************** */

    function testRewardTokenRegistryAddZeroAddrValue() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rewardToken"));
        _systemRegistry.addRewardToken(address(0));
    }

    function testRewardTokenRegistrySetOnce() public {
        address rewardToken = vm.addr(1);
        _systemRegistry.addRewardToken(rewardToken);
        assertTrue(_systemRegistry.isRewardToken(rewardToken));
    }

    function testRewardTokenRegistrySetMultiple() public {
        address rewardToken1 = vm.addr(1);

        _systemRegistry.addRewardToken(rewardToken1);
        assertTrue(_systemRegistry.isRewardToken(rewardToken1));

        address rewardToken2 = vm.addr(2);
        _systemRegistry.addRewardToken(rewardToken2);
        assertTrue(_systemRegistry.isRewardToken(rewardToken2));
    }

    function testRewardTokenRegistrySetDuplicate() public {
        address rewardToken = vm.addr(1);

        _systemRegistry.addRewardToken(rewardToken);
        assertTrue(_systemRegistry.isRewardToken(rewardToken));

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _systemRegistry.addRewardToken(rewardToken);
    }

    function testRewardTokenRegistryRemoveZeroAddrValue() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rewardToken"));
        _systemRegistry.removeRewardToken(address(0));
    }

    function testRewardTokenRegistryRemoveValue() public {
        address rewardToken = vm.addr(1);

        _systemRegistry.addRewardToken(rewardToken);
        assertTrue(_systemRegistry.isRewardToken(rewardToken));

        _systemRegistry.removeRewardToken(rewardToken);
        assertFalse(_systemRegistry.isRewardToken(rewardToken));
    }

    function testRewardTokenRegistryRemoveNonExistingValue() public {
        address rewardToken = vm.addr(123);
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _systemRegistry.removeRewardToken(rewardToken);
    }

    /* ******************************** */
    /* Swap Router
    /* ******************************** */

    function test_setSwapRouter_CanBeSetMultipleTimes() public {
        address router = vm.addr(1);
        mockSystemComponent(router);
        _systemRegistry.setSwapRouter(router);
        assertEq(address(_systemRegistry.swapRouter()), router);

        address router2 = vm.addr(2);
        mockSystemComponent(router2);
        _systemRegistry.setSwapRouter(router2);
        assertEq(address(_systemRegistry.swapRouter()), router2);
    }

    function test_setSwapRouter_CannotSetDuplicate() public {
        address router = vm.addr(1);
        mockSystemComponent(router);
        _systemRegistry.setSwapRouter(router);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(router)));
        _systemRegistry.setSwapRouter(router);
    }

    function test_setSwapRouter_EmitsEventWithNewAddress() public {
        address router = vm.addr(3);
        mockSystemComponent(router);

        vm.expectEmit(true, true, true, true);
        emit SwapRouterSet(router);

        _systemRegistry.setSwapRouter(router);
    }

    function test_setSwapRouter_OnlyCallableByOwner() public {
        address router = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setSwapRouter(router);
    }

    function test_setSwapRouter_EnsuresSystemsMatch() public {
        address router = vm.addr(1);
        address fake = vm.addr(2);
        vm.mockCall(router, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fake));
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fake));
        _systemRegistry.setSwapRouter(router);
    }

    function test_setSwapRouter_CatchesInvalidContract() public {
        // When its not a contract
        address fakeRouter = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeRouter));
        _systemRegistry.setRootPriceOracle(fakeRouter);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setSwapRouter(emptyContract);
    }

    /* ******************************** */
    /* Curve Resolver
    /* ******************************** */

    function test_setCurveResolver_CanBeSetMultipleTimes() public {
        address resolver = vm.addr(1);
        mockSystemComponent(resolver);
        _systemRegistry.setCurveResolver(resolver);
        assertEq(address(_systemRegistry.curveResolver()), resolver);

        address resolver2 = vm.addr(2);
        mockSystemComponent(resolver2);
        _systemRegistry.setCurveResolver(resolver2);
        assertEq(address(_systemRegistry.curveResolver()), resolver2);
    }

    function test_setCurveResolver_CannotSetDuplicate() public {
        address resolver = vm.addr(1);
        mockSystemComponent(resolver);
        _systemRegistry.setCurveResolver(resolver);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(resolver)));
        _systemRegistry.setCurveResolver(resolver);
    }

    function test_setCurveResolver_EmitsEventWithNewAddress() public {
        address resolver = vm.addr(3);
        mockSystemComponent(resolver);

        vm.expectEmit(true, true, true, true);
        emit CurveResolverSet(resolver);

        _systemRegistry.setCurveResolver(resolver);
    }

    function test_setCurveResolver_OnlyCallableByOwner() public {
        address resolver = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setCurveResolver(resolver);
    }

    /* ******************************** */
    /* System Security
    /* ******************************** */

    function test_setSystemSecurity_CannotBeSetToItself() public {
        address component = vm.addr(1);
        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, component));
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_CanBeSetAgain() public {
        address component = vm.addr(1);
        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
        component = vm.addr(2);
        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_ZeroAddressNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "security"));
        _systemRegistry.setSystemSecurity(address(0));
    }

    function test_setSystemSecurity_SavesValueForLaterRead() public {
        address component = vm.addr(3);
        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
        ISystemSecurity queried = _systemRegistry.systemSecurity();

        assertEq(component, address(queried));
    }

    function test_setSystemSecurity_EmitsEventOnSet() public {
        address component = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit SystemSecuritySet(component);

        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_OnlyCallableByOwner() public {
        address component = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_EnsuresSystemsMatch() public {
        address component = vm.addr(1);
        address fake = vm.addr(2);
        vm.mockCall(component, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fake));
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fake));
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_BlocksInvalidContractFromBeingSet() public {
        // When its not a contract
        address fakeComponent = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, fakeComponent));
        _systemRegistry.setSystemSecurity(fakeComponent);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setSystemSecurity(emptyContract);
    }

    /* ******************************** */
    /* Autopool Vault Factory
    /* ******************************** */

    function test_OnlyOwner_setAutopoolFactory() external {
        address fakeAutopoolFactory = vm.addr(4);
        vm.prank(vm.addr(1));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setAutopoolFactory(bytes32("Test bytes"), fakeAutopoolFactory);
    }

    function test_ZeroAddress_setAutopoolFactory() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "factoryAddress"));
        _systemRegistry.setAutopoolFactory(bytes32("Test bytes"), address(0));
    }

    function test_ZeroBytes_setAutopoolFactory() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "vaultType"));
        _systemRegistry.setAutopoolFactory(bytes32(0), vm.addr(4));
    }

    function test_ProperAdd_setAutopoolFactory() external {
        bytes32 fakeAutopoolFactoryBytes = bytes32("Fake Autopool");
        address fakeAutopoolFactory = vm.addr(4);
        mockSystemComponent(fakeAutopoolFactory);

        vm.expectEmit(false, false, false, true);
        emit AutopoolFactorySet(fakeAutopoolFactoryBytes, fakeAutopoolFactory);

        _systemRegistry.setAutopoolFactory(fakeAutopoolFactoryBytes, fakeAutopoolFactory);
        assertEq(address(_systemRegistry.getAutopoolFactoryByType(fakeAutopoolFactoryBytes)), fakeAutopoolFactory);
    }

    function test_SystemMismatch_setAutopoolFactory() external {
        address fakeRegistry = vm.addr(3);
        address fakeAutopoolFactory = vm.addr(4);

        vm.mockCall(
            fakeAutopoolFactory,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setAutopoolFactory(bytes32("Test bytes"), fakeAutopoolFactory);
    }

    function test_InvalidContract_setAutopoolFactory() external {
        address eoa = vm.addr(3);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, eoa));
        _systemRegistry.setAutopoolFactory(bytes32("Test bytes"), eoa);

        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.InvalidContract.selector, emptyContract));
        _systemRegistry.setAutopoolFactory(bytes32("Test bytes"), emptyContract);
    }

    /* ******************************** */
    /* Message proxy
    /* ******************************** */

    function test_setMessageProxy_RevertsInvalidOwner() public {
        vm.prank(makeAddr("NOT_OWNER"));
        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setMessageProxy(makeAddr("PROXY"));
    }

    function test_setMessgeProxy_RevertsDuplicate() public {
        address proxy = makeAddr("MESSAGE_PROXY");
        mockSystemComponent(proxy);

        vm.expectEmit(true, true, true, true);
        emit MessageProxySet(proxy);

        _systemRegistry.setMessageProxy(proxy);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, proxy));

        _systemRegistry.setMessageProxy(proxy);
    }

    function test_setMessageProxy_CanSetMutipleTimes() public {
        address proxy = makeAddr("MESSAGE_PROXY");
        mockSystemComponent(proxy);

        vm.expectEmit(true, true, true, true);
        emit MessageProxySet(proxy);

        _systemRegistry.setMessageProxy(proxy);

        address replacementProxy = makeAddr("REPLACEMENT");
        mockSystemComponent(replacementProxy);

        vm.expectEmit(true, true, true, true);
        emit MessageProxySet(replacementProxy);

        _systemRegistry.setMessageProxy(replacementProxy);
    }

    function test_messageProxy_ReturnsCorrectly() public {
        address proxy = makeAddr("PROXY");
        mockSystemComponent(proxy);

        _systemRegistry.setMessageProxy(proxy);

        assertEq(address(_systemRegistry.messageProxy()), proxy);
    }

    /* ******************************** */
    /* Receiving Router
    /* ******************************** */

    function test_setReceivingRouter_RevertsInvalidOwner() public {
        vm.prank(makeAddr("NOT_OWNER"));
        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setReceivingRouter(makeAddr("RECEVING_ROUTER"));
    }

    function test_setReceivingRouter_RevertsDuplicate() public {
        address router = makeAddr("RECEVING_ROUTER");
        mockSystemComponent(router);

        vm.expectEmit(true, true, true, true);
        emit ReceivingRouterSet(router);

        _systemRegistry.setReceivingRouter(router);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, router));

        _systemRegistry.setReceivingRouter(router);
    }

    function test_setRecevingRouter_CanSetMutipleTimes() public {
        address router = makeAddr("RECEIVING_ROUTER");
        mockSystemComponent(router);

        vm.expectEmit(true, true, true, true);
        emit ReceivingRouterSet(router);

        _systemRegistry.setReceivingRouter(router);

        address replacementRouter = makeAddr("REPLACEMENT");
        mockSystemComponent(replacementRouter);

        vm.expectEmit(true, true, true, true);
        emit ReceivingRouterSet(replacementRouter);

        _systemRegistry.setReceivingRouter(replacementRouter);
    }

    function test_receivingRouter_ReturnsCorrectly() public {
        address router = makeAddr("RECEIVING_ROUTER");
        mockSystemComponent(router);

        _systemRegistry.setReceivingRouter(router);

        assertEq(address(_systemRegistry.receivingRouter()), router);
    }

    /* ******************************** */
    /* Set Contract
    /* ******************************** */

    function test_setContract_RevertIf_TypeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "contractType"));
        _systemRegistry.setContract("", address(1));
    }

    function test_setContract_RevertIf_AddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "contractAddress"));
        _systemRegistry.setContract(keccak256("1"), address(0));
    }

    function test_setContract_RevertIf_AlreadySet() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(1)));
        _systemRegistry.setContract(keccak256("1"), address(1));
    }

    function test_setContract_RevertIf_NotCalledByOwner() public {
        mockSystemComponent(address(1));

        vm.startPrank(address(2));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setContract(keccak256("1"), address(1));

        vm.stopPrank();
    }

    function test_setContract_EmitsEvent() public {
        mockSystemComponent(address(1));

        vm.expectEmit(true, true, true, true);
        emit ContractSet(keccak256("1"), address(1));

        _systemRegistry.setContract(keccak256("1"), address(1));
    }

    function test_setContract_SetsValue() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));

        bool queried = _systemRegistry.isValidContract(keccak256("1"), address(1));
        assertEq(queried, true, "queried");
    }

    function test_listAdditionalContractTypes_ReturnsConfiguredValue() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));
        _systemRegistry.setContract(keccak256("2"), address(1));

        bytes32[] memory ret = _systemRegistry.listAdditionalContractTypes();
        assertEq(ret.length, 2, "len");
        assertEq(ret[0], keccak256("1"), "value");
        assertEq(ret[1], keccak256("2"), "value2");
    }

    function test_listAdditionalContractTypes_IsEmptyWhenAllRemoved() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));
        _systemRegistry.setContract(keccak256("2"), address(1));

        bytes32[] memory ret = _systemRegistry.listAdditionalContractTypes();
        assertEq(ret.length, 2, "len");
        assertEq(ret[0], keccak256("1"), "value");
        assertEq(ret[1], keccak256("2"), "value2");

        _systemRegistry.unsetContract(keccak256("1"), address(1));
        _systemRegistry.unsetContract(keccak256("2"), address(1));

        ret = _systemRegistry.listAdditionalContractTypes();
        assertEq(ret.length, 0, "len2");
    }

    function test_listAdditionalContracts_ReturnsValues() public {
        mockSystemComponent(address(1));
        mockSystemComponent(address(2));

        _systemRegistry.setContract(keccak256("1"), address(1));
        _systemRegistry.setContract(keccak256("1"), address(2));

        address[] memory ret = _systemRegistry.listAdditionalContracts(keccak256("1"));
        assertEq(ret.length, 2, "len");
        assertEq(ret[0], address(1), "value");
        assertEq(ret[1], address(2), "value2");

        _systemRegistry.unsetContract(keccak256("1"), address(1));

        ret = _systemRegistry.listAdditionalContracts(keccak256("1"));
        assertEq(ret.length, 1, "len2");
        assertEq(ret[0], address(2), "value2");

        _systemRegistry.unsetContract(keccak256("1"), address(2));

        ret = _systemRegistry.listAdditionalContracts(keccak256("1"));
        assertEq(ret.length, 0, "len3");
    }

    /* ******************************** */
    /* Unset Contract
    /* ******************************** */

    function test_unsetContract_RevertIf_TypeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "contractType"));
        _systemRegistry.unsetContract("", address(1));
    }

    function test_unsetContract_RevertIf_AddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "contractAddress"));
        _systemRegistry.unsetContract(keccak256("1"), address(0));
    }

    function test_unsetContract_RevertIf_NotAlreadySet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _systemRegistry.unsetContract(keccak256("1"), address(1));
    }

    function test_unsetContract_RevertIf_NotCalledByOwner() public {
        vm.startPrank(address(2));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.unsetContract(keccak256("1"), address(1));

        vm.stopPrank();
    }

    function test_unsetContract_UnsetsValue() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));

        bool queried = _systemRegistry.isValidContract(keccak256("1"), address(1));
        assertEq(queried, true, "queried");

        _systemRegistry.unsetContract(keccak256("1"), address(1));

        queried = _systemRegistry.isValidContract(keccak256("1"), address(1));
        assertEq(queried, false, "queried2");
    }

    function test_unsetContract_EmitsEvent() public {
        mockSystemComponent(address(1));
        _systemRegistry.setContract(keccak256("1"), address(1));

        bool queried = _systemRegistry.isValidContract(keccak256("1"), address(1));
        assertEq(queried, true, "queried");

        vm.expectEmit(true, true, true, true);
        emit ContractUnset(keccak256("1"), address(1));

        _systemRegistry.unsetContract(keccak256("1"), address(1));
    }

    /* ******************************** */
    /* Set Unique Contract
    /* ******************************** */

    function test_setUniqueContract_RevertIf_TypeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "contractType"));
        _systemRegistry.setUniqueContract("", address(1));
    }

    function test_setUniqueContract_RevertIf_AddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "contractAddress"));
        _systemRegistry.setUniqueContract(keccak256("1"), address(0));
    }

    function test_setUniqueContract_RevertIf_AlreadySet() public {
        mockSystemComponent(address(1));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        vm.expectRevert(abi.encodeWithSelector(SystemRegistryBase.DuplicateSet.selector, address(1)));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));
    }

    function test_setUniqueContract_RevertIf_NotCalledByOwner() public {
        mockSystemComponent(address(1));

        vm.startPrank(address(2));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        vm.stopPrank();
    }

    function test_setUniqueContract_EmitsEvent() public {
        mockSystemComponent(address(1));

        vm.expectEmit(true, true, true, true);
        emit UniqueContractSet(keccak256("1"), address(1));

        _systemRegistry.setUniqueContract(keccak256("1"), address(1));
    }

    function test_setUniqueContract_SetsValue() public {
        mockSystemComponent(address(1));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        address queried = _systemRegistry.getContract(keccak256("1"));
        assertEq(queried, address(1), "queried");
    }

    function test_getContract_RevertIf_ValueNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "ret"));
        _systemRegistry.getContract(keccak256("2"));
    }

    function test_listUniqueContracts_ReturnsValues() public {
        mockSystemComponent(address(1));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        (bytes32[] memory types, address[] memory addresses) = _systemRegistry.listUniqueContracts();

        assertEq(types.length, 1, "typesLen");
        assertEq(addresses.length, 1, "addressesLen");
        assertEq(types[0], keccak256("1"), "typesVal");
        assertEq(addresses[0], address(1), "addressesVal");

        _systemRegistry.unsetUniqueContract(keccak256("1"));

        (types, addresses) = _systemRegistry.listUniqueContracts();

        assertEq(types.length, 0, "typesLen");
        assertEq(addresses.length, 0, "addressesLen");
    }

    /* ******************************** */
    /* Unset Unique Contract
    /* ******************************** */

    function test_unsetUniqueContract_RevertIf_TypeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "contractType"));
        _systemRegistry.unsetUniqueContract("");
    }

    function test_unsetUniqueContract_RevertIf_NotAlreadySet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _systemRegistry.unsetUniqueContract(keccak256("1"));
    }

    function test_unsetUniqueContract_RevertIf_NotCalledByOwner() public {
        vm.startPrank(address(2));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.unsetUniqueContract(keccak256("1"));

        vm.stopPrank();
    }

    function test_unsetUniqueContract_UnsetsValue() public {
        mockSystemComponent(address(1));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        address queried = _systemRegistry.getContract(keccak256("1"));
        assertEq(queried, address(1), "queried");

        _systemRegistry.unsetUniqueContract(keccak256("1"));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "ret"));
        _systemRegistry.getContract(keccak256("1"));
    }

    function test_unsetUniqueContract_EmitsEvent() public {
        mockSystemComponent(address(1));
        _systemRegistry.setUniqueContract(keccak256("1"), address(1));

        vm.expectEmit(true, true, true, true);
        emit UniqueContractUnset(keccak256("1"));

        _systemRegistry.unsetUniqueContract(keccak256("1"));
    }

    /* ******************************** */
    /* Helpers
    /* ******************************** */

    function mockSystemComponent(address addr) internal {
        vm.mockCall(
            addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(_systemRegistry)
        );
    }
}

contract EmptyContract { }
