// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Test } from "forge-std/Test.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { LMPStrategyTestHelpers as stratHelpers } from "test/strategy/LMPStrategyTestHelpers.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract LMPVaultFactoryTest is Test {
    uint256 public constant WETH_INIT_DEPOSIT = 100_000;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    LMPVaultRegistry internal _lmpVaultRegistry;
    LMPVaultFactory internal _lmpVaultFactory;
    SystemSecurity internal _systemSecurity;

    IWETH9 internal _asset;
    TestERC20 internal _toke;

    address internal _template;
    address internal _stratTemplate;
    bytes internal lmpVaultInitData;

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

        _lmpVaultRegistry = new LMPVaultRegistry(_systemRegistry);
        _systemRegistry.setLMPVaultRegistry(address(_lmpVaultRegistry));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        // Setup the LMP Vault

        _asset = IWETH9(WETH_MAINNET);
        _systemRegistry.addRewardToken(address(_asset));
        vm.label(address(_asset), "asset");

        _template = address(new LMPVault(_systemRegistry, address(_asset), false));

        _lmpVaultFactory = new LMPVaultFactory(_systemRegistry, _template, 800, 100);
        _accessController.grantRole(Roles.LMP_VAULT_REGISTRY_UPDATER, address(_lmpVaultFactory));

        lmpVaultInitData = abi.encode("");

        _stratTemplate = address(new LMPStrategy(_systemRegistry, stratHelpers.getDefaultConfig()));
        _lmpVaultFactory.addStrategyTemplate(_stratTemplate);

        // Mock LMPVaultRouter call.
        vm.mockCall(
            address(_systemRegistry),
            abi.encodeWithSelector(SystemRegistry.lmpVaultRouter.selector),
            abi.encode(makeAddr("LMP_VAULT_ROUTER"))
        );
    }
}

contract Constructor is LMPVaultFactoryTest {
    function test_RevertIf_TemplateIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "template"));
        new LMPVaultFactory(_systemRegistry, address(0), 800, 100);
    }

    function test_SetDefaultRewardRatio() public {
        assertEq(_lmpVaultFactory.defaultRewardRatio(), 800);
    }

    function test_SetTemplate() public {
        assertEq(_lmpVaultFactory.template(), _template);
    }

    function test_SetVaultRegistry() public {
        assertEq(address(_lmpVaultFactory.vaultRegistry()), address(_lmpVaultRegistry));
    }

    function test_SetDefaultRewardBlockDuration() public {
        assertEq(_lmpVaultFactory.defaultRewardBlockDuration(), 100);
    }
}

contract AddStrategyTemplate is LMPVaultFactoryTest {
    event StrategyTemplateAdded(address template);

    function test_RevertIf_ItemAlreadyExists() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _lmpVaultFactory.addStrategyTemplate(_stratTemplate);
    }

    function test_EmitStrategyTemplateAdded() public {
        address random = makeAddr("random");

        vm.expectEmit(true, true, true, true);
        emit StrategyTemplateAdded(random);

        _lmpVaultFactory.addStrategyTemplate(random);
    }
}

contract RemoveStrategyTemplate is LMPVaultFactoryTest {
    event StrategyTemplateRemoved(address template);

    function test_RevertIf_ItemNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _lmpVaultFactory.removeStrategyTemplate(address(0));
    }

    function test_EmitStrategyTemplateRemoved() public {
        vm.expectEmit(true, true, true, true);
        emit StrategyTemplateRemoved(_stratTemplate);

        _lmpVaultFactory.removeStrategyTemplate(_stratTemplate);
    }
}

contract SetDefaultRewardRatio is LMPVaultFactoryTest {
    event DefaultRewardRatioSet(uint256 rewardRatio);

    function test_EmitDefaultRewardRatioSet() public {
        vm.expectEmit(true, true, true, true);
        emit DefaultRewardRatioSet(900);

        _lmpVaultFactory.setDefaultRewardRatio(900);
    }
}

contract SetDefaultRewardBlockDuration is LMPVaultFactoryTest {
    event DefaultBlockDurationSet(uint256 blockDuration);

    function test_EmitDefaultBlockDurationSet() public {
        vm.expectEmit(true, true, true, true);
        emit DefaultBlockDurationSet(900);

        _lmpVaultFactory.setDefaultRewardBlockDuration(900);
    }
}

contract CreateVault is LMPVaultFactoryTest {
    error InvalidStrategy();

    function test_RevertIf_NotVaultCreator() public {
        address pranker = makeAddr("pranker");
        deal(pranker, 3 ether);
        vm.startPrank(pranker);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _lmpVaultFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            _stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData
        );
    }

    function test_RevertIf_SaltIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "salt"));
        bytes32 salt = bytes32(0);

        _lmpVaultFactory.createVault{ value: WETH_INIT_DEPOSIT }(_stratTemplate, "x", "y", salt, lmpVaultInitData);
    }

    function test_RevertIf_StrategyTemplateDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(LMPVaultFactory.InvalidStrategy.selector));

        _lmpVaultFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            makeAddr("random"), "x", "y", keccak256("v1"), lmpVaultInitData
        );
    }

    function test_RevertIf_InvalidEthAmount() public {
        vm.expectRevert(abi.encodeWithSelector(LMPVaultFactory.InvalidEthAmount.selector, WETH_INIT_DEPOSIT + 1));

        _lmpVaultFactory.createVault{ value: WETH_INIT_DEPOSIT + 1 }(
            _stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData
        );
    }

    function test_AddVaultToRegistry() public {
        address newVault = _lmpVaultFactory.createVault{ value: WETH_INIT_DEPOSIT }(
            _stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData
        );

        assertTrue(_lmpVaultRegistry.isVault(newVault));
    }
}

contract GetStrategyTemplates is LMPVaultFactoryTest {
    function test_ReturnsStrategyTemplates() public {
        assertEq(_lmpVaultFactory.getStrategyTemplates()[0], _stratTemplate);
    }
}

contract IsStrategyTemplate is LMPVaultFactoryTest {
    function test_ReturnsTrueIfStrategyTemplate() public {
        assertTrue(_lmpVaultFactory.isStrategyTemplate(_stratTemplate));
    }

    function test_ReturnsFalseIfNotStrategyTemplate() public {
        assertFalse(_lmpVaultFactory.isStrategyTemplate(makeAddr("random")));
    }
}
