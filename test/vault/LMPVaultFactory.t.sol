// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { SystemRegistryBase } from "src/SystemRegistryBase.sol";
import { Test } from "forge-std/Test.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { AccessController } from "src/security/AccessController.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { AutopoolETHStrategyTestHelpers as stratHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract AutopoolFactoryTest is Test {
    uint256 public constant WETH_INIT_DEPOSIT = 100_000;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    AutopoolRegistry internal _autoPoolRegistry;
    AutopoolFactory internal _autoPoolFactory;
    SystemSecurity internal _systemSecurity;

    IWETH9 internal _asset;
    TestERC20 internal _toke;

    address internal _template;
    address internal _stratTemplate;
    bytes internal autoPoolInitData;

    // ERC20 transfer event.
    event Transfer(address indexed from, address indexed to, uint256 value);

    error InvalidEthAmount(uint256 amount);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_000_000);
        vm.warp(1000 days);

        vm.label(address(this), "testContract");

        _toke = new TestERC20("test", "test");
        vm.label(address(_toke), "toke");

        _systemRegistry = new SystemRegistry(address(_toke), WETH_MAINNET);
        _systemRegistry.addRewardToken(address(_toke));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _autoPoolRegistry = new AutopoolRegistry(_systemRegistry);
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        // Setup the Autopool Vault

        _asset = IWETH9(WETH_MAINNET);
        _systemRegistry.addRewardToken(address(_asset));
        vm.label(address(_asset), "asset");

        _template = address(new AutopoolETH(_systemRegistry, address(_asset)));

        _autoPoolFactory = new AutopoolFactory(_systemRegistry, _template, 800, 100);
        _accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(_autoPoolFactory));

        autoPoolInitData = abi.encode("");

        _stratTemplate = address(new AutopoolETHStrategy(_systemRegistry, stratHelpers.getDefaultConfig()));
        _autoPoolFactory.addStrategyTemplate(_stratTemplate);

        // Mock AutopilotRouter call.
        vm.mockCall(
            address(_systemRegistry),
            abi.encodeWithSelector(SystemRegistryBase.autoPoolRouter.selector),
            abi.encode(makeAddr("Autopool_VAULT_ROUTER"))
        );
    }
}

contract Constructor is AutopoolFactoryTest {
    function test_RevertIf_TemplateIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "template"));
        new AutopoolFactory(_systemRegistry, address(0), 800, 100);
    }

    function test_RevertIf_SystemMismatch() public {
        address fakeRegistry = makeAddr("FAKE_SYSTEM_REGISTRY");
        vm.mockCall(_template, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(fakeRegistry));

        // Don't have address of factory because this revert is in constructor, just check to make sure revert happening
        vm.expectRevert();
        new AutopoolFactory(_systemRegistry, _template, 800, 100);
    }

    function test_SetDefaultRewardRatio() public {
        assertEq(_autoPoolFactory.defaultRewardRatio(), 800);
    }

    function test_SetTemplate() public {
        assertEq(_autoPoolFactory.template(), _template);
    }

    function test_SetVaultRegistry() public {
        assertEq(address(_autoPoolFactory.vaultRegistry()), address(_autoPoolRegistry));
    }

    function test_SetDefaultRewardBlockDuration() public {
        assertEq(_autoPoolFactory.defaultRewardBlockDuration(), 100);
    }
}

contract AddStrategyTemplate is AutopoolFactoryTest {
    event StrategyTemplateAdded(address template);

    function test_RevertIf_ItemAlreadyExists() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _autoPoolFactory.addStrategyTemplate(_stratTemplate);
    }

    function test_RevertIf_SystemMismatch_StratTemplate() public {
        address fakeRegistry = makeAddr("FAKE_SYSTEM_REGISTRY");
        vm.mockCall(_stratTemplate, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(fakeRegistry));

        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, _autoPoolFactory, _stratTemplate));
        _autoPoolFactory.addStrategyTemplate(_stratTemplate);
    }

    function test_EmitStrategyTemplateAdded() public {
        address random = makeAddr("random");

        vm.mockCall(random, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(address(_systemRegistry)));

        vm.expectEmit(true, true, true, true);
        emit StrategyTemplateAdded(random);
        _autoPoolFactory.addStrategyTemplate(random);
    }
}

contract RemoveStrategyTemplate is AutopoolFactoryTest {
    event StrategyTemplateRemoved(address template);

    function test_RevertIf_ItemNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _autoPoolFactory.removeStrategyTemplate(address(0));
    }

    function test_EmitStrategyTemplateRemoved() public {
        vm.expectEmit(true, true, true, true);
        emit StrategyTemplateRemoved(_stratTemplate);

        _autoPoolFactory.removeStrategyTemplate(_stratTemplate);
    }
}

contract SetDefaultRewardRatio is AutopoolFactoryTest {
    event DefaultRewardRatioSet(uint256 rewardRatio);

    function test_EmitDefaultRewardRatioSet() public {
        vm.expectEmit(true, true, true, true);
        emit DefaultRewardRatioSet(900);

        _autoPoolFactory.setDefaultRewardRatio(900);
    }
}

contract SetDefaultRewardBlockDuration is AutopoolFactoryTest {
    event DefaultBlockDurationSet(uint256 blockDuration);

    function test_EmitDefaultBlockDurationSet() public {
        vm.expectEmit(true, true, true, true);
        emit DefaultBlockDurationSet(900);

        _autoPoolFactory.setDefaultRewardBlockDuration(900);
    }
}

contract CreateVault is AutopoolFactoryTest {
    error InvalidStrategy();

    function test_RevertIf_NotVaultCreator() public {
        address pranker = makeAddr("pranker");
        deal(pranker, 3 ether);
        vm.startPrank(pranker);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            _stratTemplate, "x", "y", keccak256("v1"), autoPoolInitData
        );
    }

    function test_RevertIf_SaltIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "salt"));
        bytes32 salt = bytes32(0);

        _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(_stratTemplate, "x", "y", salt, autoPoolInitData);
    }

    function test_RevertIf_StrategyTemplateDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(AutopoolFactory.InvalidStrategy.selector));

        _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            makeAddr("random"), "x", "y", keccak256("v1"), autoPoolInitData
        );
    }

    function test_RevertIf_InvalidEthAmount() public {
        vm.expectRevert(abi.encodeWithSelector(AutopoolFactory.InvalidEthAmount.selector, WETH_INIT_DEPOSIT + 1));

        _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT + 1 }(
            _stratTemplate, "x", "y", keccak256("v1"), autoPoolInitData
        );
    }

    function test_AddVaultToRegistry() public {
        address newVault = _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            _stratTemplate, "x", "y", keccak256("v1"), autoPoolInitData
        );

        assertTrue(_autoPoolRegistry.isVault(newVault));
    }
}

contract GetStrategyTemplates is AutopoolFactoryTest {
    function test_ReturnsStrategyTemplates() public {
        assertEq(_autoPoolFactory.getStrategyTemplates()[0], _stratTemplate);
    }
}

contract IsStrategyTemplate is AutopoolFactoryTest {
    function test_ReturnsTrueIfStrategyTemplate() public {
        assertTrue(_autoPoolFactory.isStrategyTemplate(_stratTemplate));
    }

    function test_ReturnsFalseIfNotStrategyTemplate() public {
        assertFalse(_autoPoolFactory.isStrategyTemplate(makeAddr("random")));
    }
}
