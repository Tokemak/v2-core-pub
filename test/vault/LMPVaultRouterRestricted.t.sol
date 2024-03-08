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
import { LMPStrategyTestHelpers as stratHelpers } from "test/strategy/LMPStrategyTestHelpers.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";

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
        restrictPoolUsers = true;

        forkBlock = 16_731_638;
        super.setUp();

        accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, address(this));
        accessController.grantRole(Roles.SET_WITHDRAWAL_QUEUE_ROLE, address(this));
        accessController.grantRole(Roles.AUTO_POOL_ADMIN, address(this));

        // We use mock since this function is called not from owner and
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(SystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        deal(address(baseAsset), address(this), depositAmount * 10);

        lmpVaultInitData = abi.encode("");

        lmpVault = _setupVault("v1");

        // Set rewarder as rewarder set on LMP by factory.
        lmpRewarder = lmpVault.rewarder();

        lmpVault.toggleAllowedUser(address(this));
        lmpVault.toggleAllowedUser(vm.addr(1));
        lmpVault.toggleAllowedUser(address(lmpVaultRouter));
    }

    function _setupVault(bytes memory salt) internal returns (LMPVault _lmpVault) {
        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        lmpVaultFactory.addStrategyTemplate(address(stratTemplate));

        _lmpVault =
            LMPVault(lmpVaultFactory.createVault(address(stratTemplate), "x", "y", keccak256(salt), lmpVaultInitData));
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

        assertEq(lmpVault.allowedUsers(receiver), false);
        assertEq(lmpVault.allowedUsers(user), true);
        vm.expectRevert();
        lmpVaultRouter.redeem(lmpVault, receiver, amount, 0, false);
        vm.stopPrank();

        lmpVault.toggleAllowedUser(receiver);
        assertEq(lmpVault.allowedUsers(receiver), true);
        vm.startPrank(user);
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

        assertEq(lmpVault.allowedUsers(user), true);
        assertEq(lmpVault.allowedUsers(receiver), false);
        vm.expectRevert();
        lmpVaultRouter.multicall(data);
        vm.stopPrank();

        lmpVault.toggleAllowedUser(receiver);
        assertEq(lmpVault.allowedUsers(receiver), true);

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

        vm.mockCall(vaultAddress, abi.encodeWithSignature("_checkUsers()"), abi.encode(true));

        vm.mockCall(vaultAddress, abi.encodeWithSignature("allowedUsers(address)"), abi.encode(false));

        // same data as in the ZeroExAdapter test
        // solhint-disable max-line-length
        bytes memory data =
            hex"415565b00000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000001954af4d2d99874cf0000000000000000000000000000000000000000000000000131f1a539c7e4a3cdf00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000001954af4d2d99874cf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000001761dce4c7a1693f1080000000000000000000000000000000000000000000000011a9e8a52fa524243000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000b576491f1e6e5e62f1d8f26062ee822b40b0e0d465b2489b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000001f2d26865f81e0ddf800000000000000000000000000000000000000000000000017531ae6cd92618af000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b39f68862c63935ade";

        vm.expectRevert();
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

        vm.mockCall(vaultAddress, abi.encodeWithSignature("allowedUsers(address)"), abi.encode(true));

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

    function test_deposit() public {
        uint256 amount = depositAmount;
        baseAsset.approve(address(lmpVaultRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = lmpVault.previewDeposit(amount) + 1;

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);
        vm.expectRevert();
        lmpVaultRouter.deposit(lmpVault, address(this), amount, minSharesExpected);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MinSharesError.selector));
        lmpVaultRouter.deposit(lmpVault, address(this), amount, minSharesExpected);

        // -- now do a successful scenario -- //
        _deposit(lmpVault, amount);
    }

    function test_deposit_ETH() public {
        _changeVaultToWETH();

        lmpVault.toggleAllowedUser(address(lmpVaultRouter));

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        assertEq(lmpVault.allowedUsers(address(this)), false);
        vm.expectRevert();
        lmpVaultRouter.deposit{ value: amount }(lmpVault, address(this), amount, 1);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
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

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);

        vm.expectRevert();
        lmpVaultRouter.depositMax(lmpVault, address(this), 1);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        uint256 sharesReceived = lmpVaultRouter.depositMax(lmpVault, address(this), 1);

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), 0);
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function test_mint() public {
        //lmpVault.toggleAllowedUser(address(lmpVaultRouter));
        //lmpVault.toggleAllowedUser(address(this));

        uint256 amount = depositAmount;
        // NOTE: allowance bumped up to make sure it's not what's triggering the revert (and explicitly amounts
        // returned)
        baseAsset.approve(address(lmpVaultRouter), amount * 2);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 maxAssets = lmpVault.previewMint(amount) - 1;
        baseAsset.approve(address(lmpVaultRouter), amount); // `amount` instead of `maxAssets` so that we don't

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);
        vm.expectRevert();
        lmpVaultRouter.mint(lmpVault, address(this), amount, maxAssets);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        vm.expectRevert(abi.encodeWithSelector(ILMPVaultRouterBase.MaxAmountError.selector));
        lmpVaultRouter.mint(lmpVault, address(this), amount, maxAssets);

        // -- now do a successful mint scenario -- //
        _mint(lmpVault, amount);
    }

    function test_mint_ETH() public {
        _changeVaultToWETH();

        lmpVault.toggleAllowedUser(address(lmpVaultRouter));
        assertEq(lmpVault.allowedUsers(address(lmpVaultRouter)), true);

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = lmpVault.balanceOf(address(this));

        uint256 assets = lmpVault.previewMint(amount);

        assertEq(lmpVault.allowedUsers(address(this)), false);
        vm.expectRevert();
        lmpVaultRouter.mint{ value: amount }(lmpVault, address(this), amount, assets);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        uint256 sharesReceived = lmpVaultRouter.mint{ value: amount }(lmpVault, address(this), amount, assets);

        assertEq(address(this).balance, ethBefore - amount, "ETH not withdrawn as expected");
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore + sharesReceived, "Insufficient shares received");
        assertEq(weth.balanceOf(address(this)), wethBefore, "WETH should not change");
    }

    // made it here
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

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);
        // TODO: test eth unwrap!!
        lmpVault.approve(address(lmpVaultRouter), sharesBefore);

        vm.expectRevert();
        lmpVaultRouter.withdraw(lmpVault, address(this), amount, amount, false);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
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

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);
        // TODO: test eth unwrap!!
        lmpVault.approve(address(lmpVaultRouter), sharesBefore);

        vm.expectRevert();
        lmpVaultRouter.redeem(lmpVault, address(this), amount, amount, false);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        uint256 assetsReceived = lmpVaultRouter.redeem(lmpVault, address(this), amount, amount, false);

        assertEq(assetsReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + assetsReceived);
        assertEq(lmpVault.balanceOf(address(this)), sharesBefore - amount);
    }

    function test_redeemToDeposit() public {
        uint256 amount = depositAmount;
        lmpVault2 = _setupVault("vault2");

        lmpVault2.toggleAllowedUser(address(lmpVaultRouter));

        // do deposit to vault #1 first
        uint256 sharesReceived = _deposit(lmpVault, amount);

        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));

        // -- try to fail slippage first -- //
        lmpVault.approve(address(lmpVaultRouter), amount);
        assertEq(lmpVault2.allowedUsers(address(this)), false);
        vm.expectRevert(abi.encodeWithSignature("UserNotAllowed()"));
        lmpVaultRouter.redeemToDeposit(lmpVault, lmpVault2, address(this), amount, amount + 1);

        lmpVault2.toggleAllowedUser(address(this));
        assertEq(lmpVault2.allowedUsers(address(this)), true);
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

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), false);
        vm.expectRevert();
        lmpVaultRouter.multicall(data);

        lmpVault.toggleAllowedUser(address(this));
        assertEq(lmpVault.allowedUsers(address(this)), true);
        lmpVaultRouter.multicall(data);

        // Snapshot balances after.
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 shareBalanceAfter = lmpVault.balanceOf(address(this));
        uint256 rewardBalanceAfter = lmpRewarder.balanceOf(address(this));

        assertEq(baseAssetBalanceBefore - depositAmount, baseAssetBalanceAfter); // Only `depositAmount` taken out.
        assertEq(shareBalanceAfter, 0); // Still zero, all shares should have been moved.
        assertEq(rewardBalanceAfter, expectedShares); // Should transfer 1:1.
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
        lmpVaultTemplate = address(new LMPVault(systemRegistry, address(weth), true));
        lmpVaultFactory = new LMPVaultFactory(systemRegistry, lmpVaultTemplate, 800, 100);
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(lmpVaultFactory));
        systemRegistry.setLMPVaultFactory(VaultTypes.LST, address(lmpVaultFactory));
        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        lmpVaultFactory.addStrategyTemplate(address(stratTemplate));

        lmpVault =
            LMPVault(lmpVaultFactory.createVault(address(stratTemplate), "x", "y", keccak256("weth"), lmpVaultInitData));
        assert(systemRegistry.lmpVaultRegistry().isVault(address(lmpVault)));
    }
}
