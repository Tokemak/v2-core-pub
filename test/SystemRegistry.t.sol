// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Errors } from "src/utils/Errors.sol";
import { Test, StdCheats } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";

// solhint-disable func-name-mixedcase

contract SystemRegistryTest is Test {
    SystemRegistry private _systemRegistry;

    event LMPVaultRegistrySet(address newAddress);
    event AccessControllerSet(address newAddress);
    event StatsCalculatorRegistrySet(address newAddress);
    event DestinationVaultRegistrySet(address newAddress);
    event DestinationTemplateRegistrySet(address newAddress);
    event RootPriceOracleSet(address rootPriceOracle);
    event SwapRouterSet(address swapRouter);
    event CurveResolverSet(address curveResolver);
    event SystemSecuritySet(address security);
    event LMPVaultRouterSet(address router);
    event LMPVaultFactorySet(bytes32 vaultType, address factory);
    event IncentivePricingStatsSet(address incentivePricingStats);

    function setUp() public {
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
    }

    /* ******************************** */
    /* LMP Vault Registry
    /* ******************************** */

    function testSystemRegistryLMPVaultSetOnceDuplicateValue() public {
        address lmpVault = vm.addr(1);
        mockSystemComponent(lmpVault);
        _systemRegistry.setLMPVaultRegistry(lmpVault);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "lmpVaultRegistry"));
        _systemRegistry.setLMPVaultRegistry(lmpVault);
    }

    function testSystemRegistryLMPVaultSetOnceDifferentValue() public {
        address lmpVault = vm.addr(1);
        mockSystemComponent(lmpVault);
        _systemRegistry.setLMPVaultRegistry(lmpVault);
        lmpVault = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "lmpVaultRegistry"));
        _systemRegistry.setLMPVaultRegistry(lmpVault);
    }

    function testSystemRegistryLMPVaultZeroNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lmpVaultRegistry"));
        _systemRegistry.setLMPVaultRegistry(address(0));
    }

    function testSystemRegistryLMPVaultRetrieveSetValue() public {
        address lmpVault = vm.addr(3);
        mockSystemComponent(lmpVault);
        _systemRegistry.setLMPVaultRegistry(lmpVault);
        ILMPVaultRegistry queried = _systemRegistry.lmpVaultRegistry();

        assertEq(lmpVault, address(queried));
    }

    function testSystemRegistryLMPVaultEmitsEventWithNewAddress() public {
        address lmpVault = vm.addr(3);

        vm.expectEmit(true, true, true, true);
        emit LMPVaultRegistrySet(lmpVault);

        mockSystemComponent(lmpVault);
        _systemRegistry.setLMPVaultRegistry(lmpVault);
    }

    function testSystemRegistryLMPVaultOnlyCallableByOwner() public {
        address lmpVault = vm.addr(3);
        address newOwner = vm.addr(4);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(newOwner);
        _systemRegistry.setLMPVaultRegistry(lmpVault);
    }

    function testSystemRegistryLMPVaultSystemsMatch() public {
        address lmpVault = vm.addr(1);
        address fakeRegistry = vm.addr(2);
        bytes memory registry = abi.encode(fakeRegistry);
        vm.mockCall(lmpVault, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), registry);
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setLMPVaultRegistry(lmpVault);
    }

    function testSystemRegistryLMPVaultInvalidContractCaught() public {
        // When its not a contract
        address fakeRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setLMPVaultRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setLMPVaultRegistry(emptyContract);
    }

    /* ******************************** */
    /* LMP Vault Router
    /* ******************************** */

    function test_OnlyOwner_setLMPVaultRouter() external {
        address fakeOwner = vm.addr(3);
        address fakeLMPRouter = vm.addr(4);

        vm.prank(fakeOwner);
        vm.expectRevert("Ownable: caller is not the owner");

        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);
    }

    function test_ZeroAddress_setLMPVaultRouter() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lmpVaultRouter"));
        _systemRegistry.setLMPVaultRouter(address(0));
    }

    function test_Duplicate_setLMPVaultRouter() external {
        address fakeLMPRouter = vm.addr(4);
        mockSystemComponent(fakeLMPRouter);

        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);

        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.DuplicateSet.selector, fakeLMPRouter));
        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);
    }

    function test_WorksProperly_setLMPVaultRouter() external {
        address fakeLMPRouter = vm.addr(4);
        mockSystemComponent(fakeLMPRouter);

        vm.expectEmit(false, false, false, true);
        emit LMPVaultRouterSet(fakeLMPRouter);
        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);

        assertEq(fakeLMPRouter, address(_systemRegistry.lmpVaultRouter()));
    }

    function test_SetMultipleTimes_setLMPVaultRouter() external {
        address fakeLMPRouter1 = vm.addr(4);
        address fakeLMPRouter2 = vm.addr(5);

        mockSystemComponent(fakeLMPRouter1);
        mockSystemComponent(fakeLMPRouter2);

        // First set
        vm.expectEmit(false, false, false, true);
        emit LMPVaultRouterSet(fakeLMPRouter1);
        _systemRegistry.setLMPVaultRouter(fakeLMPRouter1);
        assertEq(fakeLMPRouter1, address(_systemRegistry.lmpVaultRouter()));

        // Second set
        vm.expectEmit(false, false, false, true);
        emit LMPVaultRouterSet(fakeLMPRouter2);
        _systemRegistry.setLMPVaultRouter(fakeLMPRouter2);
        assertEq(fakeLMPRouter2, address(_systemRegistry.lmpVaultRouter()));
    }

    function test_SystemMismatch_setLMPVaultRouter() external {
        address fakeLMPRouter = vm.addr(4);
        address fakeRegistry = vm.addr(3);

        vm.mockCall(
            fakeLMPRouter, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));

        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);
    }

    function test_InvalidContract_setLMPVaultRouter() external {
        address fakeLMPRouter = vm.addr(4);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeLMPRouter));
        _systemRegistry.setLMPVaultRouter(fakeLMPRouter);

        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setLMPVaultRouter(emptyContract);
    }

    /* ******************************** */
    /* Destination Vault Registry
    /* ******************************** */

    function testSystemRegistryDestinationVaultSetOnceDuplicateValue() public {
        address destinationVault = vm.addr(1);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "destinationVaultRegistry"));
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
    }

    function testSystemRegistryDestinationVaultSetOnceDifferentValue() public {
        address destinationVault = vm.addr(1);
        mockSystemComponent(destinationVault);
        _systemRegistry.setDestinationVaultRegistry(destinationVault);
        destinationVault = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "destinationVaultRegistry"));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setDestinationVaultRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setDestinationVaultRegistry(emptyContract);
    }

    /* ******************************** */
    /* Destination Template Registry
    /* ******************************** */

    function testSystemRegistryDestinationTemplateSetOnceDuplicateValue() public {
        address destinationTemplate = vm.addr(1);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "destinationTemplateRegistry"));
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
    }

    function testSystemRegistryDestinationTemplateSetOnceDifferentValue() public {
        address destinationTemplate = vm.addr(1);
        mockSystemComponent(destinationTemplate);
        _systemRegistry.setDestinationTemplateRegistry(destinationTemplate);
        destinationTemplate = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "destinationTemplateRegistry"));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeRegistry));
        _systemRegistry.setDestinationTemplateRegistry(fakeRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeController));
        _systemRegistry.setAccessController(fakeController);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setAccessController(emptyContract);
    }

    /* ******************************** */
    /* Stats Calc Registry
    /* ******************************** */

    function testSystemRegistryStatsCalcRegistrySetOnceDuplicateValue() public {
        address statsCalcRegistry = vm.addr(1);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "statsCalculatorRegistry"));
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
    }

    function testSystemRegistryStatsCalcRegistrySetOnceDifferentValue() public {
        address statsCalcRegistry = vm.addr(1);
        mockSystemComponent(statsCalcRegistry);
        _systemRegistry.setStatsCalculatorRegistry(statsCalcRegistry);
        statsCalcRegistry = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "statsCalculatorRegistry"));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeStatsCalcRegistry));
        _systemRegistry.setStatsCalculatorRegistry(fakeStatsCalcRegistry);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
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

        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.DuplicateSet.selector, address(oracle)));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeOracle));
        _systemRegistry.setRootPriceOracle(fakeOracle);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
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

        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.DuplicateSet.selector, address(incentivePricing)));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeOracle));
        _systemRegistry.setIncentivePricingStats(fakeOracle);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
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

        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.DuplicateSet.selector, address(router)));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeRouter));
        _systemRegistry.setRootPriceOracle(fakeRouter);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
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

        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.DuplicateSet.selector, address(resolver)));
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
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "security"));
        _systemRegistry.setSystemSecurity(component);
    }

    function test_setSystemSecurity_CanOnlyBeSetOnce() public {
        address component = vm.addr(1);
        mockSystemComponent(component);
        _systemRegistry.setSystemSecurity(component);
        component = vm.addr(2);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "security"));
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
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, fakeComponent));
        _systemRegistry.setSystemSecurity(fakeComponent);

        // When it is a contract, just incorrect
        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setSystemSecurity(emptyContract);
    }

    /* ******************************** */
    /* LMP Vault Factory
    /* ******************************** */

    function test_OnlyOwner_setLMPVaultFactory() external {
        address fakeLMPFactory = vm.addr(4);
        vm.prank(vm.addr(1));

        vm.expectRevert("Ownable: caller is not the owner");
        _systemRegistry.setLMPVaultFactory(bytes32("Test bytes"), fakeLMPFactory);
    }

    function test_ZeroAddress_setLMPVaultFactory() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "factoryAddress"));
        _systemRegistry.setLMPVaultFactory(bytes32("Test bytes"), address(0));
    }

    function test_ZeroBytes_setLMPVaultFactory() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "vaultType"));
        _systemRegistry.setLMPVaultFactory(bytes32(0), vm.addr(4));
    }

    function test_ProperAdd_setLMPVaultFactory() external {
        bytes32 fakeLMPFactoryBytes = bytes32("Fake LMP");
        address fakeLMPFactory = vm.addr(4);
        mockSystemComponent(fakeLMPFactory);

        vm.expectEmit(false, false, false, true);
        emit LMPVaultFactorySet(fakeLMPFactoryBytes, fakeLMPFactory);

        _systemRegistry.setLMPVaultFactory(fakeLMPFactoryBytes, fakeLMPFactory);
        assertEq(address(_systemRegistry.getLMPVaultFactoryByType(fakeLMPFactoryBytes)), fakeLMPFactory);
    }

    function test_SystemMismatch_setLMPVaultFactory() external {
        address fakeRegistry = vm.addr(3);
        address fakeLMPFactory = vm.addr(4);

        vm.mockCall(
            fakeLMPFactory,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(fakeRegistry)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_systemRegistry), fakeRegistry));
        _systemRegistry.setLMPVaultFactory(bytes32("Test bytes"), fakeLMPFactory);
    }

    function test_InvalidContract_setLMPVaultFactory() external {
        address eoa = vm.addr(3);
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, eoa));
        _systemRegistry.setLMPVaultFactory(bytes32("Test bytes"), eoa);

        address emptyContract = address(new EmptyContract());
        vm.expectRevert(abi.encodeWithSelector(SystemRegistry.InvalidContract.selector, emptyContract));
        _systemRegistry.setLMPVaultFactory(bytes32("Test bytes"), emptyContract);
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
