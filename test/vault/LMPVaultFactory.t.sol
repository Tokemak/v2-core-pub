// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.17 <0.9.0;

// solhint-disable func-name-mixedcase,max-states-count

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";

contract LMPVaultFactoryTest is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    LMPVaultRegistry private _lmpVaultRegistry;
    LMPVaultFactory private _lmpVaultFactory;
    SystemSecurity private _systemSecurity;

    TestERC20 private _asset;
    TestERC20 private _toke;

    address private _template;
    bytes private lmpVaultInitData;

    function setUp() public {
        vm.label(address(this), "testContract");

        _toke = new TestERC20("test", "test");
        vm.label(address(_toke), "toke");

        _systemRegistry = new SystemRegistry(address(_toke), address(new TestERC20("weth", "weth")));
        _systemRegistry.addRewardToken(address(_toke));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _lmpVaultRegistry = new LMPVaultRegistry(_systemRegistry);
        _systemRegistry.setLMPVaultRegistry(address(_lmpVaultRegistry));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        // Setup the LMP Vault

        _asset = new TestERC20("asset", "asset");
        _systemRegistry.addRewardToken(address(_asset));
        vm.label(address(_asset), "asset");

        _template = address(new LMPVault(_systemRegistry, address(_asset)));

        _lmpVaultFactory = new LMPVaultFactory(_systemRegistry, _template, 800, 100);
        _accessController.grantRole(Roles.REGISTRY_UPDATER, address(_lmpVaultFactory));

        lmpVaultInitData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_001) }));

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

    function test_createVault_CreatesVaultAndAddsToRegistry() public {
        address newVault =
            _lmpVaultFactory.createVault(1_000_000, 1_000_000, "x", "y", keccak256("v1"), lmpVaultInitData);
        assertTrue(_lmpVaultRegistry.isVault(newVault));
    }

    function test_createVault_MustHaveVaultCreatorRole() public {
        vm.startPrank(address(34));
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _lmpVaultFactory.createVault(1_000_000, 1_000_000, "x", "y", keccak256("v1"), "");
        vm.stopPrank();
    }

    function test_createVault_FixesUpTokenFields() public {
        address newVault =
            _lmpVaultFactory.createVault(1_000_000, 1_000_000, "x", "y", keccak256("v1"), lmpVaultInitData);
        assertEq(IERC20(newVault).symbol(), "lmpx");
        assertEq(IERC20(newVault).name(), "y Pool Token");
    }
}
