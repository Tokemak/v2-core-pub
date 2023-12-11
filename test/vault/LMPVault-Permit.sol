// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { ERC2612 } from "test/utils/ERC2612.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";

contract PermitTests is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    LMPVaultRegistry private _lmpVaultRegistry;
    LMPVaultFactory private _lmpVaultFactory;
    SystemSecurity private _systemSecurity;

    TestERC20 private _asset;
    TestERC20 private _toke;
    LMPVault private _lmpVault;

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

        address template = address(new LMPVault(_systemRegistry, address(_asset)));

        _lmpVaultFactory = new LMPVaultFactory(_systemRegistry, template, 800, 100);
        _accessController.grantRole(Roles.REGISTRY_UPDATER, address(_lmpVaultFactory));

        bytes memory initData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_001) }));

        // Mock LMPVaultRouter call for LMPVault creation.
        vm.mockCall(
            address(_systemRegistry),
            abi.encodeWithSelector(SystemRegistry.lmpVaultRouter.selector),
            abi.encode(makeAddr("LMP_VAULT_ROUTER"))
        );

        uint256 limit = type(uint112).max;
        _lmpVault = LMPVault(_lmpVaultFactory.createVault(limit, limit, "x", "y", keccak256("v1"), initData));
        vm.label(address(_lmpVault), "lmpVault");
    }

    function test_SetUpState() public {
        assertEq(18, _lmpVault.decimals());
    }

    function test_RedeemCanPerformAsResultOfPermit() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        address spender = address(2);
        vm.label(spender, "spender");
        uint256 amount = 40e9;

        // Mints from the contract to the User
        _asset.mint(address(this), amount);
        _asset.approve(address(_lmpVault), amount);
        _lmpVault.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_lmpVault.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _lmpVault.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_lmpVault.balanceOf(user), amount);
        assertEq(_asset.balanceOf(user), 0);

        // Redeem as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _lmpVault.redeem(amount, user, user);
        vm.stopPrank();

        assertEq(_lmpVault.balanceOf(user), 0);
        assertEq(_asset.balanceOf(user), amount);
    }

    function test_WithdrawCanPerformAsResultOfPermit() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        address spender = address(2);
        vm.label(spender, "spender");
        uint256 amount = 40e9;
        address receiver = address(3);

        // Mints from the contract to the User
        _asset.mint(address(this), amount);
        _asset.approve(address(_lmpVault), amount);
        _lmpVault.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_lmpVault.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _lmpVault.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_lmpVault.balanceOf(user), amount);
        assertEq(_asset.balanceOf(user), 0);
        assertEq(_asset.balanceOf(receiver), 0);

        // Withdraw as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _lmpVault.withdraw(amount, receiver, user);
        vm.stopPrank();

        assertEq(_lmpVault.balanceOf(user), 0);
        assertEq(_asset.balanceOf(receiver), amount);
    }

    function test_TransferCanPerformAsResultOfPermit() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        address spender = address(2);
        vm.label(spender, "spender");
        uint256 amount = 40e9;
        address receiver = address(3);

        // Mints from the contract to the User
        _asset.mint(address(this), amount);
        _asset.approve(address(_lmpVault), amount);
        _lmpVault.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_lmpVault.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _lmpVault.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_lmpVault.balanceOf(user), amount);
        assertEq(_lmpVault.balanceOf(spender), 0);
        assertEq(_lmpVault.balanceOf(receiver), 0);

        // Withdraw as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _lmpVault.transferFrom(user, receiver, amount);
        vm.stopPrank();

        assertEq(_lmpVault.balanceOf(user), 0);
        assertEq(_lmpVault.balanceOf(spender), 0);
        assertEq(_lmpVault.balanceOf(receiver), amount);
    }
}
