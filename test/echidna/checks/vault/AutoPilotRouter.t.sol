// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase, no-console

import { Test } from "forge-std/Test.sol";
import { AutopilotRouterUsage } from "test/echidna/fuzz/vault/router/AutopilotRouterTests.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAutopool } from "src/vault/AutopoolETH.sol";
import { Vm } from "forge-std/Vm.sol";

contract UsageTest is AutopilotRouterUsage {
    Vm private _vm;

    constructor(Vm vm) AutopilotRouterUsage() {
        _vm = vm;
    }

    function pool() public view returns (address) {
        return address(_pool);
    }

    function router() public view returns (address) {
        return address(autoPoolRouter);
    }

    function user1() public view returns (address) {
        return _user1;
    }

    function user2() public view returns (address) {
        return _user2;
    }

    function vaultAsset() public view returns (IERC20) {
        return _vaultAsset;
    }

    function weth() public view returns (address) {
        return address(_weth);
    }

    function _startPrank(address user) internal override {
        _vm.startPrank(user);
    }

    function _stopPrank() internal override {
        _vm.stopPrank();
    }
}

contract AutopoolETHTests is Test {
    UsageTest internal usage;

    constructor() { }

    function setUp() public {
        usage = new UsageTest(vm);
    }

    function test_Construction() public {
        assertTrue(usage.pool() != address(0), "pool");
        assertTrue(usage.router() != address(0), "autoPoolRouter");
    }

    function test_Mint() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        vm.startPrank(usage.user1());
        usage.mint(1, 10_000_000, 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 10_000_000, "endShareBal");
    }

    function test_MintMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        usage.queueMint(1, 10_000_000, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 10_000_000, "endShareBal");
    }

    function test_Deposit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "endShareBal");
    }

    function test_DepositMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        usage.queueDeposit(1, 100e18, 10_000_000);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "endShareBal");
    }

    function test_SwapToDeposit() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.user1(), amount);

        // Approve
        vm.startPrank(usage.user1());
        IERC20(usage.weth()).approve(usage.router(), amount);
        vm.stopPrank();

        // Verify starting shares & balances
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.user1()), amount, "sellTokenStartBal");

        // Run swap & deposit
        vm.startPrank(usage.user1());
        usage.swapAndDepositToVault(1, amount, minSharesOut);
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), amount, "endShareBal");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.user1()), 0, "endSellTokenBal");
    }

    function test_SwapToDepositMulticall() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.user1(), amount);

        // Approve
        vm.startPrank(usage.user1());
        IERC20(usage.weth()).approve(usage.router(), amount);
        vm.stopPrank();

        // Verify starting shares & balances
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.user1()), amount, "sellTokenStartBal");

        // Queue
        usage.queueSwapAndDepositToVault(1, amount, minSharesOut);

        // Run swap & deposit
        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), amount, "endShareBal");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.user1()), 0, "endSellTokenBal");
    }

    function test_SwapToken() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.router(), amount);

        // Verify starting shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), amount, "sellTokenStartBal");

        // Run swap
        vm.startPrank(usage.user1());
        usage.swapToken(amount, minSharesOut);
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), amount, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), 0, "endSellTokenBal");
    }

    function test_SwapToken_Multicall() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.router(), amount);

        // Verify starting shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), amount, "sellTokenStartBal");

        // Enqueue swap
        usage.queueSwapToken(amount, minSharesOut);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), amount, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), 0, "endSellTokenBal");
    }

    function test_SwapTokenBalance() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.router(), amount);

        // Verify starting shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), amount, "sellTokenStartBal");

        // Run swap
        vm.startPrank(usage.user1());
        usage.swapTokenBalance(amount, minSharesOut);
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), amount, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), 0, "endSellTokenBal");
    }

    function test_SwapTokenBalance_Multicall() public {
        uint256 amount = 100e18;
        uint256 minSharesOut = amount; // imitating 1:1 swap

        // Mint some sell asset
        deal(usage.weth(), usage.router(), amount);

        // Verify starting shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "buyTokenStartBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), amount, "sellTokenStartBal");

        // Enqueue swap
        usage.queueSwapTokenBalance(amount, minSharesOut);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        // Verify ending shares & balances
        assertEq(usage.vaultAsset().balanceOf(usage.router()), amount, "endBuyTokenBal");
        assertEq(IERC20(usage.weth()).balanceOf(usage.router()), 0, "endSellTokenBal");
    }

    function test_Permit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).allowance(usage.user1(), address(usage.router())), 0, "startAllowance");

        vm.startPrank(usage.user1());
        usage.permit(1, 1, 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).allowance(usage.user1(), address(usage.router())), 100e18, "endAllowance");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 1000, 100e18);
        vm.stopPrank();
    }

    function test_PermitMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).allowance(usage.user1(), address(usage.router())), 0, "startAllowance");

        usage.queuePermit(1, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).allowance(usage.user1(), address(usage.router())), 100e18, "endAllowance");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 1000, 100e18);
        vm.stopPrank();
    }

    function test_ApproveAssets() public {
        assertEq(usage.vaultAsset().allowance(address(usage.router()), usage.user1()), 0, "startAllowance");

        vm.startPrank(usage.user1());
        usage.approveAsset(1, 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().allowance(address(usage.router()), usage.user1()), 100e18, "endAllowance");
    }

    function test_ApproveAssetsMulticall() public {
        assertEq(usage.vaultAsset().allowance(address(usage.router()), usage.user1()), 0, "startAllowance");

        usage.queueApproveAsset(1, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().allowance(address(usage.router()), usage.user1()), 100e18, "endAllowance");
    }

    function test_ApproveShares() public {
        vm.startPrank(usage.user1());
        usage.approveShare(1, 100e18);
        vm.stopPrank();
    }

    function test_ApproveSharesMulticall() public {
        assertEq(IAutopool(usage.pool()).allowance(address(usage.router()), usage.user1()), 0, "startAllowance");

        usage.queueApproveShare(1, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).allowance(address(usage.router()), usage.user1()), 100e18, "endAllowance");
    }

    function test_PullTokenFromAsset() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user2());
        usage.pullTokenFromAsset(1, 100e18, 2);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenFromAssetMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        usage.queuePullTokenFromAsset(1, 100e18, 2);

        vm.startPrank(usage.user2());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenAsset() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenAsset(100e18, 2);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenAssetMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        usage.queuePullTokenAsset(100e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenShare() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenShare(100e18, 2);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenShareMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        usage.queuePullTokenShare(100e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_PullTokenAssetRouter() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenAssetToRouter(100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.router()), 100e18, "endBal");
    }

    function test_PullTokenAssetRouterMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.router()), 0, "startBal");

        usage.queuePullTokenAssetToRouter(100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.router()), 100e18, "endBal");
    }

    function test_PullTokenShareRouter() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.router()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.router()), 100e18, "endBal");
    }

    function test_PullTokenShareRouterMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.router()), 0, "startBal");

        usage.queuePullTokenShareToRouter(100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.router()), 100e18, "endBal");
    }

    function test_SweepTokenAsset() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenAssetToRouter(100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.sweepTokenAsset(1e18, 2);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_SweepTokenAssetMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.vaultAsset().approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenAssetToRouter(100e18);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 0, "startBal");

        usage.queueSweepTokenAsset(1e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_SweepTokenShare() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.sweepTokenShare(1e18, 2);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_SweepTokenShareMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        IAutopool(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        usage.queueSweepTokenShare(1e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
    }

    function test_Redeem() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.redeem(1, 100e18, 1);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_RedeemMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueRedeem(1, 100e18, 1, false);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_Withdraw() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 100e18, 100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_WithdrawMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueWithdraw(1, 100e18, 100e18, false);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_DepositMax() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.depositMax(1, 10_000_000);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBalAsset");
    }

    function test_DepositMaxMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "startBalAsset");

        usage.queueDepositMax(1, 10_000_000);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBalAsset");
    }

    function test_DepositBalance() public {
        uint256 amount = 100e18;

        deal(address(usage.vaultAsset()), address(usage.router()), amount);

        assertEq(usage.vaultAsset().balanceOf(address(usage.router())), amount, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.depositBalance(1, amount);
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(address(usage.router())), 0, "endBalAsset");
    }

    function test_DepositBalanceMulticall() public {
        uint256 amount = 100e18;

        deal(address(usage.vaultAsset()), address(usage.router()), amount);

        assertEq(usage.vaultAsset().balanceOf(address(usage.router())), amount, "startBalAsset");

        usage.queueDepositBalance(1, amount);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(usage.vaultAsset().balanceOf(address(usage.router())), 0, "endBalAsset");
    }

    function test_StakeVaultToken() public {
        uint256 amount = 100e18;

        IERC20 poolErc = IERC20(address(usage.pool()));
        address autoPoolRewarder = address(IAutopool(usage.pool()).rewarder());

        deal(address(poolErc), address(usage.router()), amount);

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "startBalAsset");

        vm.startPrank(address(usage.router()));
        poolErc.approve(autoPoolRewarder, amount);
        vm.stopPrank();

        // User1 stakes the all the vault tokens
        vm.startPrank(usage.user1());
        usage.stakeVaultToken(amount);
        vm.stopPrank();

        assertEq(poolErc.balanceOf(address(usage.router())), 0, "endBalAsset");
    }

    function test_StakeVaultTokenMulticall() public {
        uint256 amount = 100e18;

        IERC20 poolErc = IERC20(address(usage.pool()));
        address autoPoolRewarder = address(IAutopool(usage.pool()).rewarder());

        deal(address(poolErc), address(usage.router()), amount);

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "startBalAsset");

        vm.startPrank(address(usage.router()));
        poolErc.approve(autoPoolRewarder, amount);
        vm.stopPrank();

        usage.queueStakeVaultToken(amount);

        // User1 stakes the all the vault tokens
        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(poolErc.balanceOf(address(usage.router())), 0, "endBalAsset");
    }

    function test_WithdrawVaultToken() public {
        uint256 amount = 100e18;

        IERC20 poolErc = IERC20(address(usage.pool()));
        address autoPoolRewarder = address(IAutopool(usage.pool()).rewarder());

        deal(address(poolErc), address(usage.router()), amount);

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "startBalAsset");

        vm.startPrank(address(usage.router()));
        poolErc.approve(autoPoolRewarder, amount);
        vm.stopPrank();

        // Stake the vault tokens as a router
        vm.startPrank(usage.router());
        usage.stakeVaultToken(amount);
        vm.stopPrank();

        assertEq(poolErc.balanceOf(address(usage.router())), 0, "preUnstakeBalAsset");

        // Unstake the vault tokens as a router
        vm.startPrank(usage.router());
        usage.withdrawVaultToken(amount, false);
        vm.stopPrank();

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "postUnstakeBalAsset");
    }

    function test_WithdrawVaultTokenMulticall() public {
        uint256 amount = 100e18;

        IERC20 poolErc = IERC20(address(usage.pool()));
        address autoPoolRewarder = address(IAutopool(usage.pool()).rewarder());

        deal(address(poolErc), address(usage.router()), amount);

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "startBalAsset");

        vm.startPrank(address(usage.router()));
        poolErc.approve(autoPoolRewarder, amount);
        vm.stopPrank();

        usage.queueStakeVaultToken(amount);
        usage.queueWithdrawVaultToken(amount, false);

        vm.startPrank(usage.router());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(poolErc.balanceOf(address(usage.router())), amount, "endBalAsset");
    }

    // function test_ClaimRewards() public {
    //     uint256 amount = 100e18;
    //     usage.mintAssets(1, amount);

    //     vm.startPrank(usage.user1());
    //     usage.approveAssetsToRouter(amount);
    //     vm.stopPrank();

    //     vm.startPrank(usage.user1());
    //     usage.deposit(1, amount, 10_000_000);
    //     vm.stopPrank();

    //     vm.startPrank(usage.user1());
    //     usage.approveSharesToRouter(amount);
    //     vm.stopPrank();

    //     assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), amount, "startBalShare");
    //     assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

    //     vm.startPrank(usage.router());
    //     usage.claimRewards(1, 1, amount, 1);
    //     vm.stopPrank();

    //     assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "endBalShare");
    //     assertEq(usage.vaultAsset().balanceOf(usage.user1()), amount, "endBalAsset");
    // }

    function test_RedeemMax() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.redeemMax(1, 10e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_RedeemMaxMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueRedeemMax(1, 10e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 0, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_RedeemToDeposit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        vm.startPrank(usage.user1());
        usage.redeemToDeposit(2, 10e18, 1e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
    }

    function test_RedeemToDepositMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        usage.queueRedeemToDeposit(2, 10e18, 1e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
    }

    function test_WithdrawToDeposit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        vm.startPrank(usage.user1());
        usage.withdrawToDeposit(2, 10e18, 100e18, 0.1e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
    }

    function test_WithdrawToDepositMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.approveSharesToRouter(100e18);
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        usage.queueWithdrawToDeposit(2, 10e18, 100e18, 0.1e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(IAutopool(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(IAutopool(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
    }
}
