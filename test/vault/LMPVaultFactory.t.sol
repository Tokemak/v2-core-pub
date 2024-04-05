// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Test } from "forge-std/Test.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { LMPStrategyTestHelpers as stratHelpers } from "test/strategy/LMPStrategyTestHelpers.sol";

// TODO: Delete
import { console } from "forge-std/console.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract LMPVaultFactoryTest is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    LMPVaultRegistry private _lmpVaultRegistry;
    LMPVaultFactory private _lmpVaultFactory;
    SystemSecurity private _systemSecurity;

    IWETH9 private _asset;
    TestERC20 private _toke;

    address private _template;
    address private _stratTemplate;
    bytes private lmpVaultInitData;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
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
        _accessController.grantRole(Roles.REGISTRY_UPDATER, address(_lmpVaultFactory));

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

    function test_constructor_RewardInfoSet() public {
        assertEq(_lmpVaultFactory.defaultRewardRatio(), 800);
        assertEq(_lmpVaultFactory.defaultRewardBlockDuration(), 100);
    }

    function test_setDefaultRewardRatio_UpdatesValue() public {
        assertEq(_lmpVaultFactory.defaultRewardRatio(), 800);
        _lmpVaultFactory.setDefaultRewardRatio(900);
        assertEq(_lmpVaultFactory.defaultRewardRatio(), 900);
    }

    function test_setDefaultRewardBlockDuration_UpdatesValue() public {
        assertEq(_lmpVaultFactory.defaultRewardBlockDuration(), 100);
        _lmpVaultFactory.setDefaultRewardBlockDuration(900);
        assertEq(_lmpVaultFactory.defaultRewardBlockDuration(), 900);
    }

    function test_MessageSender_Init() public {
        address vault =
            _lmpVaultFactory.createVault{ value: 100_000 }(_stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData);
        emit log_address(vault);
    }

    function test_createVault_CreatesVaultAndAddsToRegistry() public {
        address newVault = _lmpVaultFactory.createVault(_stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData);
        assertTrue(_lmpVaultRegistry.isVault(newVault));
    }

    function test_createVault_MustHaveVaultCreatorRole() public {
        vm.startPrank(address(34));
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _lmpVaultFactory.createVault(_stratTemplate, "x", "y", keccak256("v1"), "");
        vm.stopPrank();
    }

    function test_createVault_FixesUpTokenFields() public {
        address newVault = _lmpVaultFactory.createVault(_stratTemplate, "x", "y", keccak256("v1"), lmpVaultInitData);
        assertEq(IERC20(newVault).symbol(), "x");
        assertEq(IERC20(newVault).name(), "y");
    }
}
