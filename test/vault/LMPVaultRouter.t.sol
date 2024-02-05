// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { IERC20, ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";

import { AccessController } from "src/security/AccessController.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";

import { ILMPVault, LMPVault } from "src/vault/LMPVault.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { ILMPVaultFactory, LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { ILMPVaultRouterBase, ILMPVaultRouter } from "src/interfaces/vault/ILMPVaultRouter.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";
import { LMPVaultMainRewarder } from "src/rewarders/LMPVaultMainRewarder.sol";

import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";

import { BaseTest } from "test/BaseTest.t.sol";
import { WETH_MAINNET, ZERO_EX_MAINNET, CVX_MAINNET, TREASURY } from "test/utils/Addresses.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { ERC2612 } from "test/utils/ERC2612.sol";

// solhint-disable func-name-mixedcase
contract LMPVaultRouterTest is BaseTest {
    // IDestinationVault public destinationVault;
    LMPVault public lmpVault;
    LMPVault public lmpVault2;

    IMainRewarder public lmpRewarder;

    uint256 public constant MIN_DEPOSIT_AMOUNT = 100;
    uint256 public constant MAX_DEPOSIT_AMOUNT = 100 * 1e6 * 1e18; // 100mil toke
    // solhint-disable-next-line var-name-mixedcase
    uint256 public TOLERANCE = 1e14; // 0.01% (1e18 being 100%)

    uint256 public depositAmount = 1e18;

    bytes private lmpVaultInitData;

    function setUp() public override {
        forkBlock = 16_731_638;
        super.setUp();

        accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, address(this));
        accessController.grantRole(Roles.SET_WITHDRAWAL_QUEUE_ROLE, address(this));

        // We use mock since this function is called not from owner and
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(SystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        deal(address(baseAsset), address(this), depositAmount * 10);

        lmpVaultInitData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_001) }));

        lmpVault = _setupVault("v1");

        // Set rewarder as rewarder set on LMP by factory.
        lmpRewarder = lmpVault.rewarder();
    }

    function _setupVault(bytes memory salt) internal returns (LMPVault _lmpVault) {
        uint256 limit = type(uint112).max;
        _lmpVault = LMPVault(lmpVaultFactory.createVault(limit, limit, "x", "y", keccak256(salt), lmpVaultInitData));
        assert(systemRegistry.lmpVaultRegistry().isVault(address(_lmpVault)));
    }

    function test_CanRedeemThroughRouterUsingPermitForApproval() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        uint256 amount = 40e18;
        address receiver = address(3);

        // Mints to the test contract, shares to go User
        deal(address(baseAsset), address(this), amount);
        baseAsset.approve(address(lmpVaultRouter), amount);
        uint256 sharesReceived = lmpVaultRouter.deposit(lmpVault, user, amount, 0);
        assertEq(sharesReceived, lmpVault.balanceOf(user));

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            lmpVault.DOMAIN_SEPARATOR(), signerKey, user, address(lmpVaultRouter), amount, 0, deadline
        );

        vm.startPrank(user);
        lmpVaultRouter.selfPermit(address(lmpVault), amount, deadline, v, r, s);
        lmpVaultRouter.redeem(lmpVault, receiver, amount, 0, false);
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
        baseAsset.approve(address(lmpVaultRouter), amount);
        uint256 sharesReceived = lmpVaultRouter.deposit(lmpVault, user, amount, 0);
        assertEq(sharesReceived, lmpVault.balanceOf(user));

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            lmpVault.DOMAIN_SEPARATOR(), signerKey, user, address(lmpVaultRouter), amount, 0, deadline
        );

        bytes[] memory data = new bytes[](2);
        data[0] =
            abi.encodeWithSelector(lmpVaultRouter.selfPermit.selector, address(lmpVault), amount, deadline, v, r, s);
        data[1] = abi.encodeWithSelector(lmpVaultRouter.redeem.selector, lmpVault, receiver, amount, 0, false);

        vm.startPrank(user);
        lmpVaultRouter.multicall(data);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_swapAndDepositToVault() public {
        // -- Set up CVX vault for swap test -- //
        address vaultAddress = address(12);

        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        IAsyncSwapper swapper = new BaseAsyncSwapper(ZERO_EX_MAINNET);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));
        asyncSwapperRegistry.register(address(swapper));

        // -- End of CVX vault setup --//

        deal(address(CVX_MAINNET), address(this), 1e26);
        IERC20(CVX_MAINNET).approve(address(lmpVaultRouter), 1e26);

        vm.mockCall(vaultAddress, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(WETH_MAINNET));
        vm.mockCall(vaultAddress, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(100_000));

        // same data as in the ZeroExAdapter test
        // solhint-disable max-line-length
        bytes memory data =
            hex"415565b00000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000001954af4d2d99874cf0000000000000000000000000000000000000000000000000131f1a539c7e4a3cdf00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000001954af4d2d99874cf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000001761dce4c7a1693f1080000000000000000000000000000000000000000000000011a9e8a52fa524243000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000b576491f1e6e5e62f1d8f26062ee822b40b0e0d465b2489b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000001f2d26865f81e0ddf800000000000000000000000000000000000000000000000017531ae6cd92618af000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b39f68862c63935ade";
        lmpVaultRouter.swapAndDepositToVault(
            address(swapper),
            SwapParams(
                CVX_MAINNET,
                119_621_320_376_600_000_000_000,
                WETH_MAINNET,
                356_292_255_653_182_345_276,
                data,
                new bytes(0)
            ),
            ILMPVault(vaultAddress),
            address(this),
            1
        );
    }

    // TODO: fuzzing
    function test_deposit() public {
        uint256 amount = depositAmount; // TODO: fuzz
        baseAsset.approve(address(lmpVaultRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = lmpVault.previewDeposit(amount) + 1;
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MinSharesError.selector));
        lmpVaultRouter.deposit(lmpVault, address(this), amount, minSharesExpected);

        // -- now do a successful scenario -- //
        _deposit(lmpVault, amount);
    }

    // Covering https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/346-M/346-best.md
    function test_deposit_after_approve() public {
        uint256 amount = depositAmount; // TODO: fuzz
        baseAsset.approve(address(lmpVaultRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = lmpVault.previewDeposit(amount) + 1;
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MinSharesError.selector));
        lmpVaultRouter.deposit(lmpVault, address(this), amount, minSharesExpected);

        // -- pre-approve -- //
        lmpVaultRouter.approve(baseAsset, address(lmpVault), amount);
        // -- now do a successful scenario -- //
        _deposit(lmpVault, amount);
    }

    function test_deposit_ETH() public {
        _changeVaultToWETH();

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));
        uint256 sharesReceived = lmpVaultRouter.deposit{ value: amount }(lmpVault, address(this), amount, 1);

        assertEq(address(this).balance, ethBefore - amount, "ETH not withdrawn as expected");
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived, "Insufficient shares received");
        assertEq(weth.balanceOf(address(this)), wethBefore, "WETH should not change");
    }

    /// @notice Check to make sure that the whole balance gets deposited
    function test_depositMax() public {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        baseAsset.approve(address(lmpVaultRouter), baseAssetBefore);
        uint256 sharesReceived = lmpVaultRouter.depositMax(lmpVault, address(this), 1);

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), 0);
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function test_mint() public {
        uint256 amount = depositAmount;
        // NOTE: allowance bumped up to make sure it's not what's triggering the revert (and explicitly amounts
        // returned)
        baseAsset.approve(address(lmpVaultRouter), amount * 2);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 maxAssets = lmpVault.previewMint(amount) - 1;
        baseAsset.approve(address(lmpVaultRouter), amount); // `amount` instead of `maxAssets` so that we don't
            // allowance error
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MaxAmountError.selector));
        lmpVaultRouter.mint(lmpVault, address(this), amount, maxAssets);

        // -- now do a successful mint scenario -- //
        _mint(lmpVault, amount);
    }

    function test_mint_ETH() public {
        _changeVaultToWETH();

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        uint256 assets = lmpVault.previewMint(amount);

        uint256 sharesReceived = lmpVaultRouter.mint{ value: amount }(lmpVault, address(this), amount, assets);

        assertEq(address(this).balance, ethBefore - amount, "ETH not withdrawn as expected");
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived, "Insufficient shares received");
        assertEq(weth.balanceOf(address(this)), wethBefore, "WETH should not change");
    }

    function test_withdraw() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(lmpVaultRouter), amount);
        _deposit(lmpVault, amount);

        // -- try to fail slippage first by allowing a little less shares than it would need-- //
        lmpVault.approve(address(lmpVaultRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MaxSharesError.selector));
        lmpVaultRouter.withdraw(lmpVault, address(this), amount, amount - 1, false);

        // -- now test a successful withdraw -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        // TODO: test eth unwrap!!
        lmpVault.approve(address(lmpVaultRouter), sharesBefore);
        uint256 sharesOut = lmpVaultRouter.withdraw(lmpVault, address(this), amount, amount, false);

        assertEq(sharesOut, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + amount);
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore - sharesOut);
    }

    function test_redeem() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(lmpVaultRouter), amount);
        _deposit(lmpVault, amount);

        // -- try to fail slippage first by requesting a little more assets than we can get-- //
        lmpVault.approve(address(lmpVaultRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MinAmountError.selector));
        lmpVaultRouter.redeem(lmpVault, address(this), amount, amount + 1, false);

        // -- now test a successful redeem -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        // TODO: test eth unwrap!!
        lmpVault.approve(address(lmpVaultRouter), sharesBefore);
        uint256 assetsReceived = lmpVaultRouter.redeem(lmpVault, address(this), amount, amount, false);

        assertEq(assetsReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + assetsReceived);
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore - amount);
    }

    function test_redeemToDeposit() public {
        uint256 amount = depositAmount;
        lmpVault2 = _setupVault("vault2");

        // do deposit to vault #1 first
        uint256 sharesReceived = _deposit(lmpVault, amount);

        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));

        // -- try to fail slippage first -- //
        lmpVault.approve(address(lmpVaultRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MinSharesError.selector));
        lmpVaultRouter.redeemToDeposit(lmpVault, lmpVault2, address(this), amount, amount + 1);

        // -- now try a successful redeemToDeposit scenario -- //

        // Do actual `redeemToDeposit` call
        lmpVault.approve(address(lmpVaultRouter), sharesReceived);
        uint256 newSharesReceived = lmpVaultRouter.redeemToDeposit(lmpVault, lmpVault2, address(this), amount, amount);

        // Check final state
        assertEq(newSharesReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore, "Base asset amount should not change");
        assertEq(lmpVault.balanceOf(address(this)), 0, "Shares in vault #1 should be 0 after the move");
        assertEq(lmpVault2.balanceOf(address(this)), newSharesReceived, "Shares in vault #2 should be increased");
    }

    // All three rewarder based functions use same path to check for valid vault, use stake to test all.
    function test_RevertsOnInvalidVault() public {
        // No need to approve, deposit to vault, etc, revert will happen before transfer.
        vm.expectRevert(Errors.ItemNotFound.selector);
        lmpVaultRouter.stakeVaultToken(IERC20(makeAddr("NOT_LMP_VAULT")), depositAmount);
    }

    function test_stakeVaultToken_Router() public {
        // Get reward and vault balances of `address(this)` before.
        uint256 shareBalanceBefore = _deposit(lmpVault, depositAmount);
        uint256 stakedBalanceBefore = lmpRewarder.balanceOf(address(this));
        uint256 rewarderShareBalanceBefore = lmpVault.balanceOf(address(lmpRewarder));

        // Checks pre stake.
        assertEq(shareBalanceBefore, depositAmount); // First deposit, no supply yet, mints 1:1.
        assertEq(stakedBalanceBefore, 0); // User has not staked yet.
        assertEq(rewarderShareBalanceBefore, 0); // Nothing in rewarder yet.

        // Approve rewarder and stake via router.
        lmpVault.approve(address(lmpVaultRouter), shareBalanceBefore);
        lmpVaultRouter.stakeVaultToken(IERC20(address(lmpVault)), shareBalanceBefore);

        // Reward and balances of `address(this)` after stake.
        uint256 shareBalanceAfter = lmpVault.balanceOf(address(this));
        uint256 stakedBalanceAfter = lmpRewarder.balanceOf(address(this));
        uint256 rewarderShareBalanceAfter = lmpVault.balanceOf(address(lmpRewarder));

        // Post stake checks.
        assertEq(shareBalanceAfter, 0); // All shares should be staked.
        assertEq(stakedBalanceAfter, shareBalanceBefore); // Staked balance should be 1:1 shares.
        assertEq(rewarderShareBalanceAfter, shareBalanceBefore); // Should own all shares.
    }

    function test_RevertRewarderDoesNotExist_withdraw() public {
        // Doesn't need to stake first, checks before actual withdrawal
        vm.expectRevert(Errors.ItemNotFound.selector);
        lmpVaultRouter.withdrawVaultToken(lmpVault, IMainRewarder(makeAddr("FAKE_REWARDER")), 1, false);
    }

    function test_WithdrawFromPastRewarder() public {
        // Deposit, approve, stake.
        uint256 shareBalanceBefore = _deposit(lmpVault, depositAmount);
        lmpVault.approve(address(lmpVaultRouter), shareBalanceBefore);
        lmpVaultRouter.stakeVaultToken(lmpVault, shareBalanceBefore);

        // Replace rewarder.
        address newRewarder = address(
            new LMPVaultMainRewarder(systemRegistry, address(new MockERC20()), 1000, 1000, true, address(lmpVault))
        );
        vm.mockCall(
            address(accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.LMP_REWARD_MANAGER_ROLE, address(this)),
            abi.encode(true)
        );
        lmpVault.setRewarder(newRewarder);

        // Make sure correct rewarder set.
        assertEq(address(lmpVault.rewarder()), newRewarder);
        assertTrue(lmpVault.isPastRewarder(address(lmpRewarder)));

        uint256 userBalanceInPastRewarderBefore = lmpRewarder.balanceOf(address(this));
        uint256 userBalanceLMPTokenBefore = lmpVault.balanceOf(address(this));

        assertEq(userBalanceInPastRewarderBefore, shareBalanceBefore);
        assertEq(userBalanceLMPTokenBefore, 0);

        // Fake rewarder - 0x002C41f924b4f3c0EE3B65749c4481f7cc9Dea03
        // Real rewarder - 0xc1A7C52ED8c7671a56e8626e7ae362334480f599

        lmpVaultRouter.withdrawVaultToken(lmpVault, lmpRewarder, shareBalanceBefore, false);

        uint256 userBalanceInPastRewarderAfter = lmpRewarder.balanceOf(address(this));
        uint256 userBalanceLMPTokenAfter = lmpVault.balanceOf(address(this));

        assertEq(userBalanceInPastRewarderAfter, 0);
        assertEq(userBalanceLMPTokenAfter, shareBalanceBefore);
    }

    function test_withdrawVaultToken_NoClaim_Router() public {
        // Stake first.
        uint256 shareBalanceBefore = _deposit(lmpVault, depositAmount);
        lmpVault.approve(address(lmpVaultRouter), shareBalanceBefore);
        lmpVaultRouter.stakeVaultToken(IERC20(address(lmpVault)), shareBalanceBefore);

        // Make sure balances match expected.
        assertEq(lmpVault.balanceOf(address(this)), 0); // All shares transferred out.
        assertEq(lmpVault.balanceOf(address(lmpRewarder)), shareBalanceBefore); // All shares owned by rewarder.
        assertEq(lmpRewarder.balanceOf(address(this)), shareBalanceBefore); // Should mint 1:1 for shares.

        // Withdraw half of shares.
        lmpVaultRouter.withdrawVaultToken(lmpVault, lmpRewarder, shareBalanceBefore, false);

        assertEq(lmpVault.balanceOf(address(this)), shareBalanceBefore); // All shares should be returned to user.
        assertEq(lmpVault.balanceOf(address(lmpRewarder)), 0); // All shares transferred out.
        assertEq(lmpRewarder.balanceOf(address(this)), 0); // Balance should be properly adjusted.
    }

    function test_withdrawVaultToken_Claim_Router() public {
        uint256 localStakeAmount = 1000;

        // Grant liquidator role to treasury to allow queueing of Toke rewards.
        // Neccessary because rewarder uses Toke as reward token.
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, TREASURY);

        // Make sure Toke is not going to be sent to GPToke contract.
        assertEq(lmpRewarder.tokeLockDuration(), 0);

        // Prank treasury to approve rewarder and queue toke rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(lmpRewarder), localStakeAmount);
        lmpRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to LMP.
        uint256 sharesReceived = _deposit(lmpVault, depositAmount);

        // Stake LMP
        lmpVault.approve(address(lmpVaultRouter), sharesReceived);
        lmpVaultRouter.stakeVaultToken(IERC20(address(lmpVault)), sharesReceived);

        // Snapshot values before withdraw.
        uint256 stakeBalanceBefore = lmpRewarder.balanceOf(address(this));
        uint256 shareBalanceBefore = lmpVault.balanceOf(address(this));
        uint256 rewarderBalanceRewardTokenBefore = toke.balanceOf(address(lmpRewarder));
        uint256 userBalanceRewardTokenBefore = toke.balanceOf(address(this));

        assertEq(stakeBalanceBefore, sharesReceived); // Amount staked should be total shares minted.
        assertEq(shareBalanceBefore, 0); // User should have transferred all assets out.
        assertEq(rewarderBalanceRewardTokenBefore, localStakeAmount); // All reward should still be in rewarder.
        assertEq(userBalanceRewardTokenBefore, 0); // User should have no reward token before withdrawal.

        // Roll for entire reward duration, gives all rewards to user.  100 is reward duration.
        vm.roll(block.number + 100);

        // Unstake.
        lmpVaultRouter.withdrawVaultToken(lmpVault, lmpRewarder, depositAmount, true);

        // Snapshot balances after withdrawal.
        uint256 stakeBalanceAfter = lmpRewarder.balanceOf(address(this));
        uint256 shareBalanceAfter = lmpVault.balanceOf(address(this));
        uint256 rewarderBalanceRewardTokenAfter = toke.balanceOf(address(lmpRewarder));
        uint256 userBalanceRewardTokenAfter = toke.balanceOf(address(this));

        assertEq(stakeBalanceAfter, 0); // All should be unstaked for user.
        assertEq(shareBalanceAfter, depositAmount); // All shares should be returned to user.
        assertEq(rewarderBalanceRewardTokenAfter, 0); // All should be transferred to user.
        assertEq(userBalanceRewardTokenAfter, localStakeAmount); // User should now own all reward tokens.
    }

    function test_RevertRewarderDoesNotExist_claim() public {
        vm.expectRevert(Errors.ItemNotFound.selector);
        lmpVaultRouter.claimRewards(lmpVault, IMainRewarder(makeAddr("FAKE_REWARDER")));
    }

    function test_ClaimFromPastRewarder() public {
        uint256 localStakeAmount = 1000;

        // Grant treasury liquidator role, allows queueing of rewards.
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, TREASURY);

        // Check Toke lock duration.
        assertEq(lmpRewarder.tokeLockDuration(), 0);

        // Prank treasury, queue rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(lmpRewarder), localStakeAmount);
        lmpRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to vault.
        uint256 sharesReceived = _deposit(lmpVault, depositAmount);

        // Stake to rewarder.
        lmpVault.approve(address(lmpVaultRouter), sharesReceived);
        lmpVaultRouter.stakeVaultToken(lmpVault, sharesReceived);

        // Roll block for reward claiming.
        vm.roll(block.number + 100);

        // Create new rewarder, set as rewarder on LMP vault.
        LMPVaultMainRewarder newRewarder =
            new LMPVaultMainRewarder(systemRegistry, address(new MockERC20()), 100, 100, false, address(lmpVault));
        vm.mockCall(
            address(accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.LMP_REWARD_MANAGER_ROLE, address(this)),
            abi.encode(true)
        );
        lmpVault.setRewarder(address(newRewarder));

        // Make sure rewarder set as past.
        assertTrue(lmpVault.isPastRewarder(address(lmpRewarder)));

        // Snapshot and checks.
        uint256 userRewardsPastRewarderBefore = lmpRewarder.earned(address(this));
        uint256 userRewardTokenBalanceBefore = toke.balanceOf(address(this));
        assertEq(userRewardsPastRewarderBefore, localStakeAmount);

        // Claim rewards.
        lmpVaultRouter.claimRewards(lmpVault, lmpRewarder);

        // Snapshot and checks.
        uint256 userClaimedRewards = toke.balanceOf(address(this));
        assertEq(userRewardTokenBalanceBefore + userClaimedRewards, localStakeAmount);
    }

    function test_claimRewards_Router() public {
        uint256 localStakeAmount = 1000;

        // Grant liquidator role to treasury to allow queueing of Toke rewards.
        // Neccessary because rewarder uses Toke as reward token.
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, TREASURY);

        // Make sure Toke is not going to be sent to GPToke contract.
        assertEq(lmpRewarder.tokeLockDuration(), 0);

        // Prank treasury to approve rewarder and queue toke rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(lmpRewarder), localStakeAmount);
        lmpRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to LMP.
        uint256 sharesReceived = _deposit(lmpVault, depositAmount);

        // Stake LMP
        lmpVault.approve(address(lmpVaultRouter), sharesReceived);
        lmpVaultRouter.stakeVaultToken(IERC20(address(lmpVault)), sharesReceived);

        assertEq(toke.balanceOf(address(this)), 0); // Make sure no Toke for user before claim.
        assertEq(toke.balanceOf(address(lmpRewarder)), localStakeAmount); // Rewarder has proper amount before claim.

        // Roll for entire reward duration, gives all rewards to user.  100 is reward duration.
        vm.roll(block.number + 100);

        lmpVaultRouter.claimRewards(lmpVault, lmpRewarder);

        assertEq(toke.balanceOf(address(this)), localStakeAmount); // Make sure all toke transferred to user.
        assertEq(toke.balanceOf(address(lmpRewarder)), 0); // Rewarder should have no toke left.
    }

    function test_DepositAndStakeMulticall() public {
        // Need data array with two members, deposit to lmp and stake to rewarder.  Approvals done beforehand.
        bytes[] memory data = new bytes[](2);

        // Approve router, rewarder. Max approvals to make it easier.
        baseAsset.approve(address(lmpVaultRouter), type(uint256).max);
        lmpVault.approve(address(lmpVaultRouter), type(uint256).max);

        // Get preview of shares for staking.
        uint256 expectedShares = lmpVault.previewDeposit(depositAmount);

        // Generate data.
        data[0] = abi.encodeWithSelector(lmpVaultRouter.deposit.selector, lmpVault, address(this), depositAmount, 1); // Deposit
        data[1] =
            abi.encodeWithSelector(lmpVaultRouter.stakeVaultToken.selector, IERC20(address(lmpVault)), expectedShares);

        // Snapshot balances for user (address(this)) before multicall.
        uint256 baseAssetBalanceBefore = baseAsset.balanceOf(address(this));
        uint256 shareBalanceBefore = lmpVault.balanceOf(address(this));
        uint256 rewardBalanceBefore = lmpRewarder.balanceOf(address(this));

        // Check snapshots.
        assertGe(baseAssetBalanceBefore, depositAmount); // Make sure there is at least enough to deposit.
        assertEq(shareBalanceBefore, 0); // No deposit, should be zero.
        assertEq(rewardBalanceBefore, 0); // No rewards yet, should be zero.

        // Execute multicall.
        lmpVaultRouter.multicall(data);

        // Snapshot balances after.
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 shareBalanceAfter = lmpVault.balanceOf(address(this));
        uint256 rewardBalanceAfter = lmpRewarder.balanceOf(address(this));

        assertEq(baseAssetBalanceBefore - depositAmount, baseAssetBalanceAfter); // Only `depositAmount` taken out.
        assertEq(shareBalanceAfter, 0); // Still zero, all shares should have been moved.
        assertEq(rewardBalanceAfter, expectedShares); // Should transfer 1:1.
    }

    function test_withdrawStakeAndWithdrawMulticall() public {
        // Deposit and stake normally.
        baseAsset.approve(address(lmpVaultRouter), depositAmount);
        uint256 shares = lmpVaultRouter.deposit(lmpVault, address(this), depositAmount, 1);
        lmpVault.approve(address(lmpVaultRouter), shares);
        lmpVaultRouter.stakeVaultToken(IERC20(address(lmpVault)), shares);

        // Need array of bytes with two members, one for unstaking from rewarder, other for withdrawing from LMP.
        bytes[] memory data = new bytes[](2);

        // Approve router to burn share tokens.
        lmpVault.approve(address(lmpVaultRouter), shares);

        // Generate data.
        uint256 rewardBalanceBefore = lmpRewarder.balanceOf(address(this));
        data[0] = abi.encodeWithSelector(
            lmpVaultRouter.withdrawVaultToken.selector, lmpVault, lmpRewarder, rewardBalanceBefore, false
        );
        data[1] = abi.encodeWithSelector(
            lmpVaultRouter.redeem.selector, lmpVault, address(this), rewardBalanceBefore, 1, false
        );

        // Snapshot balances for `address(this)` before call.
        uint256 baseAssetBalanceBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBalanceBefore = lmpVault.balanceOf(address(this));

        // Check snapshots.  Don't check baseAsset balance here, check after multicall to make sure correct amount
        // comes back.
        assertEq(rewardBalanceBefore, shares); // All shares minted should be in rewarder.
        assertEq(sharesBalanceBefore, 0); // User should own no shares.

        // Execute multicall.
        lmpVaultRouter.multicall(data);

        // Post multicall snapshot.
        uint256 rewardBalanceAfter = lmpRewarder.balanceOf(address(this));
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 sharesBalanceAfter = lmpVault.balanceOf(address(this));

        assertEq(rewardBalanceAfter, 0); // All rewards removed.
        assertEq(baseAssetBalanceAfter, baseAssetBalanceBefore + depositAmount); // Should have all base asset back.
        assertEq(sharesBalanceAfter, 0); // All shares burned.
    }

    function test_stakeWorksWith_MaxAmountGreaterThanUserBalance() public {
        baseAsset.approve(address(lmpVaultRouter), depositAmount);
        uint256 shares = lmpVaultRouter.deposit(lmpVault, address(this), depositAmount, 1);

        lmpVault.approve(address(lmpVaultRouter), type(uint256).max);
        lmpVaultRouter.stakeVaultToken(lmpVault, type(uint256).max);

        // Should only deposit amount of shares user has.
        assertEq(lmpRewarder.balanceOf(address(this)), shares);
    }

    function test_withdrawWorksWith_MaxAmountGreaterThanUsersBalance() public {
        baseAsset.approve(address(lmpVaultRouter), depositAmount);
        uint256 shares = lmpVaultRouter.deposit(lmpVault, address(this), depositAmount, 1);

        lmpVault.approve(address(lmpVaultRouter), shares);
        lmpVaultRouter.stakeVaultToken(lmpVault, shares);

        lmpVaultRouter.withdrawVaultToken(lmpVault, lmpRewarder, type(uint256).max, false);

        assertEq(lmpVault.balanceOf(address(this)), shares);
    }

    /* **************************************************************************** */
    /* 				    	    	Helper methods									*/

    function _deposit(LMPVault _lmpVault, uint256 amount) private returns (uint256 sharesReceived) {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = _lmpVault.balanceOf(address(this));

        baseAsset.approve(address(lmpVaultRouter), amount);
        sharesReceived = lmpVaultRouter.deposit(_lmpVault, address(this), amount, 1);

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore - amount);
        assertEq(_lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function _mint(LMPVault _lmpVault, uint256 shares) private returns (uint256 assets) {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = _lmpVault.balanceOf(address(this));

        baseAsset.approve(address(lmpVaultRouter), shares);
        assets = _lmpVault.previewMint(shares);
        assets = lmpVaultRouter.mint(_lmpVault, address(this), shares, assets);

        assertGt(assets, 0);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore - assets);
        assertEq(_lmpVault.balanceOf(address(this)), sharesBefore + shares);
    }

    // @dev ETH needs special handling, so for a few tests that need to use ETH, this shortcut converts baseAsset to
    // WETH
    function _changeVaultToWETH() private {
        //
        // Update factory to support WETH instead of regular mock (one time just for this test)
        //
        lmpVaultTemplate = address(new LMPVault(systemRegistry, address(weth)));
        lmpVaultFactory = new LMPVaultFactory(systemRegistry, lmpVaultTemplate, 800, 100);
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(lmpVaultFactory));
        systemRegistry.setLMPVaultFactory(VaultTypes.LST, address(lmpVaultFactory));

        uint256 limit = type(uint112).max;
        lmpVault = LMPVault(lmpVaultFactory.createVault(limit, limit, "x", "y", keccak256("weth"), lmpVaultInitData));
        assert(systemRegistry.lmpVaultRegistry().isVault(address(lmpVault)));
    }
}
