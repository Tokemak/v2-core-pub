// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase, no-console

import { Test } from "forge-std/Test.sol";
import { LMPVaultRouterUsage } from "test/echidna/fuzz/vault/router/LMPVaultRouterTests.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ILMPVault } from "src/vault/LMPVault.sol";
import { Vm } from "forge-std/Vm.sol";

contract UsageTest is LMPVaultRouterUsage {
    Vm private _vm;

    constructor(Vm vm) LMPVaultRouterUsage() {
        _vm = vm;
    }

    function pool() public view returns (address) {
        return address(_pool);
    }

    function router() public view returns (address) {
        return address(lmpVaultRouter);
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

    function _startPrank(address user) internal override {
        _vm.startPrank(user);
    }

    function _stopPrank() internal override {
        _vm.stopPrank();
    }
}

contract LMPVaultTests is Test {
    UsageTest internal usage;

    constructor() { }

    function setUp() public {
        usage = new UsageTest(vm);
    }

    function test_Construction() public {
        assertTrue(usage.pool() != address(0), "pool");
        assertTrue(usage.router() != address(0), "lmpVaultRouter");
    }

    function test_Mint() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        vm.startPrank(usage.user1());
        usage.mint(1, 10_000_000, 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 10_000_000, "endShareBal");
    }

    function test_MintMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        usage.queueMint(1, 10_000_000, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 10_000_000, "endShareBal");
    }

    function test_Deposit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "endShareBal");
    }

    function test_DepositMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startShareBal");

        usage.queueDeposit(1, 100e18, 10_000_000);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "endShareBal");
    }

    function test_Permit() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.deposit(1, 100e18, 10_000_000);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).allowance(usage.user1(), address(usage.router())), 0, "startAllowance");

        vm.startPrank(usage.user1());
        usage.permit(1, 1, 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).allowance(usage.user1(), address(usage.router())), 100e18, "endAllowance");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 1000, 100e18, false);
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

        assertEq(ILMPVault(usage.pool()).allowance(usage.user1(), address(usage.router())), 0, "startAllowance");

        usage.queuePermit(1, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).allowance(usage.user1(), address(usage.router())), 100e18, "endAllowance");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 1000, 100e18, false);
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
        assertEq(ILMPVault(usage.pool()).allowance(address(usage.router()), usage.user1()), 0, "startAllowance");

        usage.queueApproveShare(1, 100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).allowance(address(usage.router()), usage.user1()), 100e18, "endAllowance");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenShare(100e18, 2);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        usage.queuePullTokenShare(100e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.router()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.router()), 100e18, "endBal");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.router()), 0, "startBal");

        usage.queuePullTokenShareToRouter(100e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.router()), 100e18, "endBal");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        vm.startPrank(usage.user1());
        usage.sweepTokenShare(1e18, 2);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
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
        ILMPVault(usage.pool()).approve(usage.router(), 100e18);
        vm.stopPrank();

        vm.startPrank(usage.user1());
        usage.pullTokenShareToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0, "startBal");

        usage.queueSweepTokenShare(1e18, 2);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 100e18, "endBal");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.redeem(1, 100e18, 1, false);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueRedeem(1, 100e18, 1, false);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.withdraw(1, 100e18, 100e18, false);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueWithdraw(1, 100e18, 100e18, false);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "endBalAsset");
    }

    function test_DepositMax() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.depositMax(1, 10_000_000);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBalAsset");
    }

    function test_DepositMaxMulticall() public {
        usage.mintAssets(1, 100e18);

        vm.startPrank(usage.user1());
        usage.approveAssetsToRouter(100e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 100e18, "startBalAsset");

        usage.queueDepositMax(1, 10_000_000);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "endBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "endBalAsset");
    }

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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        vm.startPrank(usage.user1());
        usage.redeemMax(1, 10e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "endBalShare");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare");
        assertEq(usage.vaultAsset().balanceOf(usage.user1()), 0, "startBalAsset");

        usage.queueRedeemMax(1, 10e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 0, "endBalShare");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        vm.startPrank(usage.user1());
        usage.redeemToDeposit(2, 10e18, 1e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        usage.queueRedeemToDeposit(2, 10e18, 1e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        vm.startPrank(usage.user1());
        usage.withdrawToDeposit(2, 10e18, 100e18, 0.1e18);
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
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

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 100e18, "startBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 0e18, "startBalShare2");

        usage.queueWithdrawToDeposit(2, 10e18, 100e18, 0.1e18);

        vm.startPrank(usage.user1());
        usage.executeMulticall();
        vm.stopPrank();

        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user1()), 90e18, "endBalShare1");
        assertEq(ILMPVault(usage.pool()).balanceOf(usage.user2()), 10e18, "endBalShare2");
    }
}
