// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count,max-line-length

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { ERC2612 } from "test/utils/ERC2612.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { SystemRegistryBase } from "src/SystemRegistryBase.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";
import { AutopoolETHStrategyTestHelpers as stratHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";
import { TestWETH9 } from "test/mocks/TestWETH9.sol";

contract PermitTests is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    AutopoolRegistry private _autoPoolRegistry;
    AutopoolFactory private _autoPoolFactory;
    SystemSecurity private _systemSecurity;

    TestERC20 private _asset;
    TestERC20 private _toke;
    AutopoolETH private _autoPool;
    TestWETH9 private _weth;

    function setUp() public {
        vm.warp(1000 days);

        vm.label(address(this), "testContract");

        _weth = new TestWETH9();

        _toke = new TestERC20("test", "test");
        vm.label(address(_toke), "toke");

        _systemRegistry = new SystemRegistry(address(_toke), address(_weth));
        _systemRegistry.addRewardToken(address(_toke));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _autoPoolRegistry = new AutopoolRegistry(_systemRegistry);
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        // Setup the Autopool Vault

        _asset = TestERC20(address(_weth));
        _systemRegistry.addRewardToken(address(_asset));
        vm.label(address(_asset), "asset");

        AutopoolETH template = new AutopoolETH(_systemRegistry, address(_asset));
        uint256 autoPoolInitDeposit = template.WETH_INIT_DEPOSIT();

        _autoPoolFactory = new AutopoolFactory(_systemRegistry, address(template), 800, 100);
        _accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(_autoPoolFactory));

        bytes memory initData = abi.encode("");

        AutopoolETHStrategy strategyTemplate = new AutopoolETHStrategy(_systemRegistry, stratHelpers.getDefaultConfig());
        _autoPoolFactory.addStrategyTemplate(address(strategyTemplate));

        // Mock AutopilotRouter call for AutopoolETH creation.
        vm.mockCall(
            address(_systemRegistry),
            abi.encodeWithSelector(SystemRegistryBase.autoPoolRouter.selector),
            abi.encode(makeAddr("Autopool_VAULT_ROUTER"))
        );

        _autoPool = AutopoolETH(
            _autoPoolFactory.createVault{ value: autoPoolInitDeposit }(
                address(strategyTemplate), "x", "y", keccak256("v1"), initData
            )
        );
        vm.label(address(_autoPool), "autoPool");
    }

    function test_SetUpState() public {
        assertEq(18, _autoPool.decimals());
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
        _asset.approve(address(_autoPool), amount);
        _autoPool.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_autoPool.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _autoPool.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_autoPool.balanceOf(user), amount);
        assertEq(_asset.balanceOf(user), 0);

        // Redeem as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _autoPool.redeem(amount, user, user);
        vm.stopPrank();

        assertEq(_autoPool.balanceOf(user), 0);
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
        _asset.approve(address(_autoPool), amount);
        _autoPool.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_autoPool.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _autoPool.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_autoPool.balanceOf(user), amount);
        assertEq(_asset.balanceOf(user), 0);
        assertEq(_asset.balanceOf(receiver), 0);

        // Withdraw as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _autoPool.withdraw(amount, receiver, user);
        vm.stopPrank();

        assertEq(_autoPool.balanceOf(user), 0);
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
        _asset.approve(address(_autoPool), amount);
        _autoPool.deposit(amount, user);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) =
            ERC2612.getPermitSignature(_autoPool.DOMAIN_SEPARATOR(), signerKey, user, spender, amount, 0, deadline);

        // Execute the permit as the contract
        _autoPool.permit(user, spender, amount, deadline, v, r, s);

        assertEq(_autoPool.balanceOf(user), amount);
        assertEq(_autoPool.balanceOf(spender), 0);
        assertEq(_autoPool.balanceOf(receiver), 0);

        // Withdraw as the Spender back to the User, mimicking the router here
        vm.startPrank(spender);
        _autoPool.transferFrom(user, receiver, amount);
        vm.stopPrank();

        assertEq(_autoPool.balanceOf(user), 0);
        assertEq(_autoPool.balanceOf(spender), 0);
        assertEq(_autoPool.balanceOf(receiver), amount);
    }
}
