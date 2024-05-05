// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";

import { IAutoPool, AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { AutoPoolFactory } from "src/vault/AutoPoolFactory.sol";
import { IAutoPilotRouterBase } from "src/interfaces/vault/IAutoPilotRouter.sol";

import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

import { Roles } from "src/libs/Roles.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";

import { BaseTest } from "test/BaseTest.t.sol";
import { WETH_MAINNET, ZERO_EX_MAINNET, CVX_MAINNET } from "test/utils/Addresses.sol";

import { ERC2612 } from "test/utils/ERC2612.sol";
import { LMPStrategyTestHelpers as stratHelpers } from "test/strategy/LMPStrategyTestHelpers.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";

// solhint-disable func-name-mixedcase
contract AutoPilotRouterTest is BaseTest {
    // IDestinationVault public destinationVault;
    AutoPoolETH public autoPool;
    AutoPoolETH public autoPool2;

    IMainRewarder public autoPoolRewarder;

    uint256 public constant MIN_DEPOSIT_AMOUNT = 100;
    uint256 public constant MAX_DEPOSIT_AMOUNT = 100 * 1e6 * 1e18; // 100mil toke
    // solhint-disable-next-line var-name-mixedcase
    uint256 public TOLERANCE = 1e14; // 0.01% (1e18 being 100%)

    uint256 public depositAmount = 1e18;

    bytes private autoPoolInitData;

    function setUp() public override {
        restrictPoolUsers = true;

        forkBlock = 16_731_638;
        super.setUp();

        accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(autoPoolFactory));

        // We use mock since this function is called not from owner and
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(SystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        deal(address(baseAsset), address(this), depositAmount * 10);

        autoPoolInitData = abi.encode("");

        autoPool = _setupVault("v1");

        autoPool.toggleAllowedUser(address(this));
        autoPool.toggleAllowedUser(vm.addr(1));
        autoPool.toggleAllowedUser(address(autoPoolRouter));

        // Set rewarder as rewarder set on LMP by factory.
        autoPoolRewarder = autoPool.rewarder();
    }

    function _setupVault(bytes memory salt) internal returns (AutoPoolETH _autoPool) {
        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        _autoPool = AutoPoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256(salt), autoPoolInitData
            )
        );
        assert(systemRegistry.autoPoolRegistry().isVault(address(_autoPool)));
    }

    function test_CanRedeemThroughRouterUsingPermitForApproval() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        uint256 amount = 40e18;
        address receiver = address(3);

        // Mints to the test contract, shares to go User
        deal(address(baseAsset), address(this), amount);
        baseAsset.approve(address(autoPoolRouter), amount);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, user, amount, 0));

        bytes[] memory results = autoPoolRouter.multicall(calls);

        uint256 sharesReceived = abi.decode(results[2], (uint256));

        assertEq(sharesReceived, autoPool.balanceOf(user));

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            autoPool.DOMAIN_SEPARATOR(), signerKey, user, address(autoPoolRouter), amount, 0, deadline
        );

        vm.startPrank(user);
        autoPoolRouter.selfPermit(address(autoPool), amount, deadline, v, r, s);

        assertEq(autoPool.allowedUsers(receiver), false);
        assertEq(autoPool.allowedUsers(user), true);
        vm.expectRevert();
        autoPoolRouter.redeem(autoPool, receiver, amount, 0);
        vm.stopPrank();

        autoPool.toggleAllowedUser(receiver);
        assertEq(autoPool.allowedUsers(receiver), true);
        vm.startPrank(user);
        autoPoolRouter.redeem(autoPool, receiver, amount, 0);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_CanRedeemThroughRouterUsingPermitForApprovalViaMulticall() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        uint256 amount = 40e18;
        address receiver = address(3);

        // Mints to the test contract, shares to go User
        deal(address(baseAsset), address(this), amount);
        baseAsset.approve(address(autoPoolRouter), amount);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, user, amount, 0));

        bytes[] memory results = autoPoolRouter.multicall(calls);

        uint256 sharesReceived = abi.decode(results[2], (uint256));
        assertEq(sharesReceived, autoPool.balanceOf(user));

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            autoPool.DOMAIN_SEPARATOR(), signerKey, user, address(autoPoolRouter), amount, 0, deadline
        );

        bytes[] memory data = new bytes[](2);
        data[0] =
            abi.encodeWithSelector(autoPoolRouter.selfPermit.selector, address(autoPool), amount, deadline, v, r, s);
        data[1] = abi.encodeWithSelector(autoPoolRouter.redeem.selector, autoPool, receiver, amount, 0, false);

        vm.startPrank(user);

        assertEq(autoPool.allowedUsers(user), true);
        assertEq(autoPool.allowedUsers(receiver), false);
        vm.expectRevert();
        autoPoolRouter.multicall(data);
        vm.stopPrank();

        autoPool.toggleAllowedUser(receiver);
        assertEq(autoPool.allowedUsers(receiver), true);

        vm.startPrank(user);
        autoPoolRouter.multicall(data);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_swapAndDepositToVault() public {
        // -- Set up CVX vault for swap test -- //
        address vaultAddress = address(12);

        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        IAsyncSwapper swapper = new BaseAsyncSwapper(ZERO_EX_MAINNET);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
        asyncSwapperRegistry.register(address(swapper));

        // -- End of CVX vault setup --//

        uint256 amount = 1e26;
        deal(address(CVX_MAINNET), address(this), amount);
        IERC20(CVX_MAINNET).approve(address(autoPoolRouter), amount);

        vm.mockCall(vaultAddress, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(WETH_MAINNET));
        vm.mockCall(vaultAddress, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(100_000));

        vm.mockCall(vaultAddress, abi.encodeWithSignature("_checkUsers()"), abi.encode(true));

        vm.mockCall(vaultAddress, abi.encodeWithSignature("allowedUsers(address)"), abi.encode(false));

        // same data as in the ZeroExAdapter test
        // solhint-disable max-line-length
        bytes memory data =
            hex"415565b00000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000001954af4d2d99874cf0000000000000000000000000000000000000000000000000131f1a539c7e4a3cdf00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000001954af4d2d99874cf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000001761dce4c7a1693f1080000000000000000000000000000000000000000000000011a9e8a52fa524243000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000b576491f1e6e5e62f1d8f26062ee822b40b0e0d465b2489b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000001f2d26865f81e0ddf800000000000000000000000000000000000000000000000017531ae6cd92618af000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b39f68862c63935ade";

        SwapParams memory swapParams = SwapParams(
            CVX_MAINNET, 119_621_320_376_600_000_000_000, WETH_MAINNET, 356_292_255_653_182_345_276, data, new bytes(0)
        );

        vm.mockCall(vaultAddress, abi.encodeWithSignature("allowedUsers(address)"), abi.encode(true));

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (IERC20(CVX_MAINNET), amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.swapToken, (address(swapper), swapParams));
        calls[2] = abi.encodeCall(autoPoolRouter.depositBalance, (IAutoPool(vaultAddress), address(this), 1));
        autoPoolRouter.multicall(calls);
    }

    function test_deposit() public {
        uint256 amount = depositAmount;
        baseAsset.approve(address(autoPoolRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = autoPool.previewDeposit(amount) + 1;

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, minSharesExpected));

        vm.expectRevert();
        bytes[] memory results = autoPoolRouter.multicall(calls);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        vm.expectRevert(abi.encodeWithSelector(IAutoPilotRouterBase.MinSharesError.selector));
        results = autoPoolRouter.multicall(calls);

        // -- now do a successful scenario -- //
        _deposit(autoPool, amount);
    }

    function test_deposit_ETH() public {
        _changeVaultToWETH();

        autoPool.toggleAllowedUser(address(autoPoolRouter));

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        assertEq(autoPool.allowedUsers(address(this)), false);

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("wrapWETH9(uint256)", amount);
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (weth, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, 1));

        vm.expectRevert();
        autoPoolRouter.multicall{ value: amount }(calls);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);

        bytes[] memory results = autoPoolRouter.multicall{ value: amount }(calls);

        uint256 sharesReceived = abi.decode(results[2], (uint256));

        assertEq(address(this).balance, ethBefore - amount, "ETH not withdrawn as expected");
        assertEq(autoPool.balanceOf(address(this)), sharesBefore + sharesReceived, "Insufficient shares received");
        assertEq(weth.balanceOf(address(this)), wethBefore, "WETH should not change");
    }

    /// @notice Check to make sure that the whole balance gets deposited
    function test_depositMax() public {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        baseAsset.approve(address(autoPoolRouter), baseAssetBefore);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);

        vm.expectRevert();
        autoPoolRouter.depositMax(autoPool, address(this), 1);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        uint256 sharesReceived = autoPoolRouter.depositMax(autoPool, address(this), 1);

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), 0);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function test_mintAA() public {
        //autoPool.toggleAllowedUser(address(autoPoolRouter));
        //autoPool.toggleAllowedUser(address(this));

        uint256 amount = depositAmount;
        // NOTE: allowance bumped up to make sure it's not what's triggering the revert (and explicitly amounts
        // returned)
        baseAsset.approve(address(autoPoolRouter), amount * 2);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 maxAssets = autoPool.previewMint(amount) - 1;
        baseAsset.approve(address(autoPoolRouter), amount); // `amount` instead of `maxAssets` so that we don't

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.mint, (autoPool, address(this), amount, maxAssets));

        vm.expectRevert();
        autoPoolRouter.multicall(calls);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        vm.expectRevert(abi.encodeWithSelector(IAutoPilotRouterBase.MaxAmountError.selector));
        autoPoolRouter.multicall(calls);

        // // -- now do a successful mint scenario -- //
        _mint(autoPool, amount);
    }

    function test_mint_ETH() public {
        _changeVaultToWETH();

        autoPool.toggleAllowedUser(address(autoPoolRouter));
        assertEq(autoPool.allowedUsers(address(autoPoolRouter)), true);

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        uint256 assets = autoPool.previewMint(amount);

        assertEq(autoPool.allowedUsers(address(this)), false);
        vm.expectRevert();
        autoPoolRouter.mint{ value: amount }(autoPool, address(this), amount, assets);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("wrapWETH9(uint256)", amount);
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (weth, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, 1));

        bytes[] memory results = autoPoolRouter.multicall{ value: amount }(calls);

        uint256 sharesReceived = abi.decode(results[2], (uint256));

        assertEq(address(this).balance, ethBefore - amount, "ETH not withdrawn as expected");
        assertEq(autoPool.balanceOf(address(this)), sharesBefore + sharesReceived, "Insufficient shares received");
        assertEq(weth.balanceOf(address(this)), wethBefore, "WETH should not change");
    }

    // made it here
    function test_withdraw() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        // -- try to fail slippage first by allowing a little less shares than it would need-- //
        autoPool.approve(address(autoPoolRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(IAutoPilotRouterBase.MaxSharesError.selector));
        autoPoolRouter.withdraw(autoPool, address(this), amount, amount - 1);

        // -- now test a successful withdraw -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);
        // TODO: test eth unwrap!!
        autoPool.approve(address(autoPoolRouter), sharesBefore);

        vm.expectRevert();
        autoPoolRouter.withdraw(autoPool, address(this), amount, amount);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        uint256 sharesOut = autoPoolRouter.withdraw(autoPool, address(this), amount, amount);

        assertEq(sharesOut, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + amount);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore - sharesOut);
    }

    function test_redeem() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        // -- try to fail slippage first by requesting a little more assets than we can get-- //
        autoPool.approve(address(autoPoolRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(IAutoPilotRouterBase.MinAmountError.selector));
        autoPoolRouter.redeem(autoPool, address(this), amount, amount + 1);

        // -- now test a successful redeem -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);
        // TODO: test eth unwrap!!
        autoPool.approve(address(autoPoolRouter), sharesBefore);

        vm.expectRevert();
        autoPoolRouter.redeem(autoPool, address(this), amount, amount);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        uint256 assetsReceived = autoPoolRouter.redeem(autoPool, address(this), amount, amount);

        assertEq(assetsReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + assetsReceived);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore - amount);
    }

    function test_redeemToDeposit() public {
        uint256 amount = depositAmount;
        autoPool2 = _setupVault("vault2");

        autoPool2.toggleAllowedUser(address(autoPoolRouter));

        // do deposit to vault #1 first
        uint256 sharesReceived = _deposit(autoPool, amount);

        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));

        // -- try to fail slippage first -- //
        autoPool.approve(address(autoPoolRouter), amount);
        assertEq(autoPool2.allowedUsers(address(this)), false);
        vm.expectRevert(abi.encodeWithSignature("InvalidUser()"));
        autoPoolRouter.redeemToDeposit(autoPool, autoPool2, address(this), amount, amount + 1);

        autoPool2.toggleAllowedUser(address(this));
        assertEq(autoPool2.allowedUsers(address(this)), true);
        vm.expectRevert(abi.encodeWithSelector(IAutoPilotRouterBase.MinSharesError.selector));
        autoPoolRouter.redeemToDeposit(autoPool, autoPool2, address(this), amount, amount + 1);

        // -- now try a successful redeemToDeposit scenario -- //

        // Do actual `redeemToDeposit` call
        autoPool.approve(address(autoPoolRouter), sharesReceived);
        uint256 newSharesReceived = autoPoolRouter.redeemToDeposit(autoPool, autoPool2, address(this), amount, amount);

        // Check final state
        assertEq(newSharesReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore, "Base asset amount should not change");
        assertEq(autoPool.balanceOf(address(this)), 0, "Shares in vault #1 should be 0 after the move");
        assertEq(autoPool2.balanceOf(address(this)), newSharesReceived, "Shares in vault #2 should be increased");
    }

    function test_DepositAndStakeMulticall() public {
        // Approve router, rewarder. Max approvals to make it easier.
        baseAsset.approve(address(autoPoolRouter), type(uint256).max);
        autoPool.approve(address(autoPoolRouter), type(uint256).max);

        // Get preview of shares for staking.
        uint256 expectedShares = autoPool.previewDeposit(depositAmount);

        // Generate data.
        // data[0] = abi.encodeWithSelector(autoPoolRouter.deposit.selector, autoPool, address(this), depositAmount, 1);
        // // Deposit
        // data[1] =
        //     abi.encodeWithSelector(autoPoolRouter.stakeVaultToken.selector, IERC20(address(autoPool)),
        // expectedShares);

        bytes[] memory calls = new bytes[](6);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, depositAmount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), depositAmount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), depositAmount, 0));

        calls[3] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, expectedShares, address(autoPoolRouter)));
        calls[4] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), expectedShares));
        calls[5] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, expectedShares));

        // Snapshot balances for user (address(this)) before multicall.
        uint256 baseAssetBalanceBefore = baseAsset.balanceOf(address(this));
        uint256 shareBalanceBefore = autoPool.balanceOf(address(this));
        uint256 rewardBalanceBefore = autoPoolRewarder.balanceOf(address(this));

        // Check snapshots.
        assertGe(baseAssetBalanceBefore, depositAmount); // Make sure there is at least enough to deposit.
        assertEq(shareBalanceBefore, 0); // No deposit, should be zero.
        assertEq(rewardBalanceBefore, 0); // No rewards yet, should be zero.

        // Execute multicall.

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), false);
        vm.expectRevert();
        autoPoolRouter.multicall(calls);

        autoPool.toggleAllowedUser(address(this));
        assertEq(autoPool.allowedUsers(address(this)), true);
        autoPoolRouter.multicall(calls);

        // Snapshot balances after.
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 shareBalanceAfter = autoPool.balanceOf(address(this));
        uint256 rewardBalanceAfter = autoPoolRewarder.balanceOf(address(this));

        assertEq(baseAssetBalanceBefore - depositAmount, baseAssetBalanceAfter); // Only `depositAmount` taken out.
        assertEq(shareBalanceAfter, 0); // Still zero, all shares should have been moved.
        assertEq(rewardBalanceAfter, expectedShares); // Should transfer 1:1.
    }

    /* **************************************************************************** */
    /* 				    	    	Helper methods									*/

    function _deposit(AutoPoolETH _autoPool, uint256 amount) private returns (uint256 sharesReceived) {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = _autoPool.balanceOf(address(this));

        baseAsset.approve(address(autoPoolRouter), amount);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(_autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (_autoPool, address(this), amount, 0));

        bytes[] memory results = autoPoolRouter.multicall(calls);

        sharesReceived = abi.decode(results[2], (uint256));

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore - amount);
        assertEq(_autoPool.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function _mint(AutoPoolETH _autoPool, uint256 shares) private returns (uint256 assets) {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = _autoPool.balanceOf(address(this));

        baseAsset.approve(address(autoPoolRouter), shares);
        assets = _autoPool.previewMint(shares);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, assets, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(_autoPool), assets));
        calls[2] = abi.encodeCall(autoPoolRouter.mint, (_autoPool, address(this), shares, assets));

        autoPoolRouter.multicall(calls);

        assertGt(assets, 0);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore - assets);
        assertEq(_autoPool.balanceOf(address(this)), sharesBefore + shares);
    }

    // @dev ETH needs special handling, so for a few tests that need to use ETH, this shortcut converts baseAsset to
    // WETH
    function _changeVaultToWETH() private {
        //
        // Update factory to support WETH instead of regular mock (one time just for this test)
        //
        autoPoolTemplate = address(new AutoPoolETH(systemRegistry, address(weth), true));
        autoPoolFactory = new AutoPoolFactory(systemRegistry, autoPoolTemplate, 800, 100);
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(autoPoolFactory));
        systemRegistry.setAutoPoolFactory(VaultTypes.LST, address(autoPoolFactory));
        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        autoPool = AutoPoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256("weth"), autoPoolInitData
            )
        );
        assert(systemRegistry.autoPoolRegistry().isVault(address(autoPool)));
    }
}
