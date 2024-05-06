// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable one-contract-per-file,avoid-low-level-calls */

import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISelfPermit } from "src/interfaces/utils/ISelfPermit.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";
import { AutopoolMainRewarder } from "src/rewarders/AutopoolMainRewarder.sol";

import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { IAutopilotRouterBase, IAutopilotRouter } from "src/interfaces/vault/IAutopilotRouter.sol";

import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IRewards } from "src/interfaces/rewarders/IRewards.sol";
import { Rewards } from "src/rewarders/Rewards.sol";

import { Roles } from "src/libs/Roles.sol";
import { PeripheryPayments } from "src/utils/PeripheryPayments.sol";
import { Errors } from "src/utils/Errors.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";

import { BaseTest } from "test/BaseTest.t.sol";
import { WETH_MAINNET, ZERO_EX_MAINNET, CVX_MAINNET, TREASURY, WETH9_ADDRESS } from "test/utils/Addresses.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { ERC2612 } from "test/utils/ERC2612.sol";
import { AutopoolETHStrategyTestHelpers as stratHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";

import { Vm } from "forge-std/Vm.sol";

contract AutopilotRouterWrapper is AutopilotRouter {
    error SomethingWentWrong();

    event SomethingHappened();

    constructor(ISystemRegistry _systemRegistry) AutopilotRouter(_systemRegistry) { }

    function doSomethingWrong() public pure {
        revert SomethingWentWrong();
    }

    function doSomethingRight() public {
        emit SomethingHappened();
    }
}

/// @dev Custom mocked swapper for testing to represent a 1:1 swap
contract SwapperMock is BaseAsyncSwapper, BaseTest {
    error ETHSwapFailed();

    constructor(address _aggregator) BaseAsyncSwapper(_aggregator) { }

    function swap(SwapParams memory params) public override returns (uint256 buyTokenAmountReceived) {
        // Mock 1:1 swap

        deal(address(this), params.buyAmount);
        (bool success,) = payable(WETH9_ADDRESS).call{ value: params.buyAmount }("");
        if (!success) revert ETHSwapFailed();
        IERC20(WETH9_ADDRESS).transfer(msg.sender, params.buyAmount);
        return params.buyAmount;
    }
}

// solhint-disable func-name-mixedcase
contract AutopilotRouterTest is BaseTest {
    // IDestinationVault public destinationVault;
    AutopoolETH public autoPool;
    AutopoolETH public autoPool2;

    IMainRewarder public autoPoolRewarder;
    Rewards public rewards;
    Vm.Wallet public rewardsSigner;

    uint256 public constant MIN_DEPOSIT_AMOUNT = 100;
    uint256 public constant MAX_DEPOSIT_AMOUNT = 100 * 1e6 * 1e18; // 100mil toke
    // solhint-disable-next-line var-name-mixedcase
    uint256 public TOLERANCE = 1e14; // 0.01% (1e18 being 100%)

    uint256 public depositAmount = 1e18;

    bytes private autoPoolInitData;

    function setUp() public override {
        forkBlock = 16_731_638;
        super.setUp();

        accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        // We use mock since this function is called not from owner and
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(SystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        deal(address(baseAsset), address(this), depositAmount * 10);

        autoPoolInitData = abi.encode("");

        autoPool = _setupVault("v1");

        // Set rewarder as rewarder set on Autopool by factory.
        autoPoolRewarder = autoPool.rewarder();

        rewardsSigner = vm.createWallet(string("signer"));
        rewards = new Rewards(systemRegistry, IERC20(address(autoPool)), rewardsSigner.addr);
    }

    function _setupVault(bytes memory salt) internal returns (AutopoolETH _autoPool) {
        AutopoolETHStrategy stratTemplate = new AutopoolETHStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        _autoPool = AutopoolETH(
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
        autoPoolRouter.redeem(autoPool, receiver, amount, 0);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_CanRedeemThroughRouterUsingPermitWhenFrontRun() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        address frontRunner = vm.addr(2);
        vm.label(frontRunner, "frontRunner");
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

        // Front run the user
        vm.prank(frontRunner);
        IERC20Permit(address(autoPool)).permit(user, address(autoPoolRouter), amount, deadline, v, r, s);

        vm.startPrank(user);
        autoPoolRouter.selfPermit(address(autoPool), amount, deadline, v, r, s);
        autoPoolRouter.redeem(autoPool, receiver, amount, 0);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_CannotRedeemThroughRouterUsingPermitWhenAllowanceExceeded() public {
        uint256 signerKey = 1;
        address user = vm.addr(signerKey);
        vm.label(user, "user");
        address frontRunner = vm.addr(2);
        vm.label(frontRunner, "frontRunner");
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

        // Front run the user
        vm.prank(frontRunner);
        IERC20Permit(address(autoPool)).permit(user, address(autoPoolRouter), amount, deadline, v, r, s);

        // And then spend the some user tokens (reduce allowance)
        IERC20(address(autoPool)).approve(address(autoPoolRouter), amount / 2);

        vm.startPrank(user);
        autoPoolRouter.selfPermit(address(autoPool), amount, deadline, v, r, s);
        autoPoolRouter.redeem(autoPool, receiver, amount, 0);

        // Should revert because allowance is insufficient
        vm.expectRevert(abi.encodeWithSelector(ISelfPermit.PermitFailed.selector));
        autoPoolRouter.selfPermit(address(autoPool), amount, deadline, v, r, s);
        vm.stopPrank();
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
        autoPoolRouter.multicall(data);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(receiver), amount);
    }

    function test_swapAndDepositToVaultViaMultiCall() public {
        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        IAsyncSwapper swapper = new BaseAsyncSwapper(ZERO_EX_MAINNET);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
        asyncSwapperRegistry.register(address(swapper));

        uint256 amount = 1e26;
        deal(address(CVX_MAINNET), address(this), amount);
        IERC20(CVX_MAINNET).approve(address(autoPoolRouter), amount);

        uint256 vaultBalanceBefore = autoPool.balanceOf(address(this));
        uint256 cvxBalanceBefore = IERC20(CVX_MAINNET).balanceOf(address(this));
        bytes[] memory calls = new bytes[](3);

        // same data as in the ZeroExAdapter test
        // solhint-disable max-line-length
        bytes memory data =
            hex"415565b00000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000001954af4d2d99874cf0000000000000000000000000000000000000000000000000131f1a539c7e4a3cdf00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000001954af4d2d99874cf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000001761dce4c7a1693f1080000000000000000000000000000000000000000000000011a9e8a52fa524243000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000b576491f1e6e5e62f1d8f26062ee822b40b0e0d465b2489b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000001f2d26865f81e0ddf800000000000000000000000000000000000000000000000017531ae6cd92618af000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b39f68862c63935ade";

        SwapParams memory swapParams = SwapParams(
            CVX_MAINNET, 119_621_320_376_600_000_000_000, WETH_MAINNET, 356_292_255_653_182_345_276, data, new bytes(0)
        );

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (IERC20(CVX_MAINNET), amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.swapToken, (address(swapper), swapParams));
        calls[2] = abi.encodeCall(autoPoolRouter.depositBalance, (autoPool, address(this), 0));

        autoPoolRouter.multicall(calls);

        uint256 vaultBalanceAfter = autoPool.balanceOf(address(this));
        uint256 cvxBalanceAfter = IERC20(CVX_MAINNET).balanceOf(address(this));

        assertGt(vaultBalanceAfter, vaultBalanceBefore);
        assertLt(cvxBalanceAfter, cvxBalanceBefore);
        assert(autoPool.balanceOf(address(autoPoolRouter)) == 0);
    }

    function test_deposit() public {
        uint256 amount = depositAmount;
        baseAsset.approve(address(autoPoolRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = autoPool.previewDeposit(amount) + 1;
        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, minSharesExpected));

        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinSharesError.selector));
        autoPoolRouter.multicall(calls);

        // -- now do a successful scenario -- //
        _deposit(autoPool, amount);
    }

    // Covering https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/346-M/346-best.md
    function test_deposit_after_approve() public {
        uint256 amount = depositAmount; // TODO: fuzz
        baseAsset.approve(address(autoPoolRouter), amount);

        // -- try to fail slippage first -- //
        // set threshold for just over what's expected
        uint256 minSharesExpected = autoPool.previewDeposit(amount) + 1;

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, minSharesExpected));

        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinSharesError.selector));
        autoPoolRouter.multicall(calls);

        // -- pre-approve -- //
        autoPoolRouter.approve(baseAsset, address(autoPool), amount);
        // -- now do a successful scenario -- //
        _deposit(autoPool, amount);
    }

    function test_deposit_ETH() public {
        _changeVaultToWETH();

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

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

    /// @notice Check to make sure that the whole balance gets deposited
    function test_depositMax() public {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        baseAsset.approve(address(autoPoolRouter), baseAssetBefore);
        uint256 sharesReceived = autoPoolRouter.depositMax(autoPool, address(this), 1);

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), 0);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function test_mintA() public {
        uint256 amount = depositAmount;

        // -- try to fail slippage first -- //
        // // set threshold for just over what's expected
        uint256 maxAssets = autoPool.previewMint(amount) - 1;
        baseAsset.approve(address(autoPoolRouter), amount); // `amount` instead of `maxAssets` so that we don't
        // // allowance error

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.mint, (autoPool, address(this), amount, maxAssets));

        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MaxAmountError.selector));
        autoPoolRouter.multicall(calls);

        // -- now do a successful mint scenario -- //
        _mint(autoPool, amount);
    }

    function test_mint_ETH() public {
        _changeVaultToWETH();

        uint256 amount = depositAmount;

        vm.deal(address(this), amount);

        uint256 ethBefore = address(this).balance;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        autoPool.previewMint(amount);

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

    function test_claim_rewards() public {
        uint256 amount = depositAmount;
        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);
        autoPool.transfer(address(rewards), amount);

        assertEq(autoPool.balanceOf(address(this)), 0, "Vault token balance should be empty");

        IRewards.Recipient memory recipient =
            IRewards.Recipient({ chainId: block.chainid, cycle: 1, wallet: address(this), amount: amount });

        bytes32 hashedRecipient = rewards.genHash(recipient);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardsSigner, hashedRecipient);

        vm.startPrank(address(2));
        vm.expectRevert(Errors.AccessDenied.selector);
        autoPoolRouter.claimRewards(rewards, recipient, v, r, s);
        vm.stopPrank();

        uint256 claimedAmount = autoPoolRouter.claimRewards(rewards, recipient, v, r, s);

        assertEq(claimedAmount, amount, "should claim full amount from rewards");

        assertEq(autoPool.balanceOf(address(this)), amount, "Vault token balance should be back to normal");
    }

    function test_redeem_on_claim_rewards() public {
        uint256 amount = depositAmount;
        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);
        autoPool.transfer(address(rewards), amount);
        autoPool.approve(address(autoPoolRouter), amount);

        assertEq(autoPool.balanceOf(address(this)), 0, "Vault token balance should be empty");

        IRewards.Recipient memory recipient =
            IRewards.Recipient({ chainId: block.chainid, cycle: 1, wallet: address(this), amount: amount });

        bytes32 hashedRecipient = rewards.genHash(recipient);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardsSigner, hashedRecipient);

        uint256 prevBaseAssetBalance = baseAsset.balanceOf(address(this));

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IAutopilotRouter.claimRewards, (IRewards(rewards), recipient, v, r, s));
        calls[1] = abi.encodeCall(autoPoolRouter.redeem, (autoPool, address(this), amount, 1));

        autoPoolRouter.multicall(calls);

        uint256 newBaseAssetBalance = baseAsset.balanceOf(address(this));

        assertEq(autoPool.balanceOf(address(this)), 0, "Vault token balance should still be 0");
        assertEq(
            newBaseAssetBalance - prevBaseAssetBalance, depositAmount, "Rewards should be redeemed into base asset"
        );
    }

    function test_withdraw() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        // -- try to fail slippage first by allowing a little less shares than it would need-- //
        autoPool.approve(address(autoPoolRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MaxSharesError.selector));
        autoPoolRouter.withdraw(autoPool, address(this), amount, amount - 1);

        // -- now test a successful withdraw -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        // // TODO: test eth unwrap!!
        autoPool.approve(address(autoPoolRouter), sharesBefore);
        uint256 sharesOut = autoPoolRouter.withdraw(autoPool, address(this), amount, amount);

        assertEq(sharesOut, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + amount);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore - sharesOut);
    }

    function test_swap_on_withdraw() public {
        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        IAsyncSwapper swapperMock = new SwapperMock(address(123));
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
        asyncSwapperRegistry.register(address(swapperMock));
        uint256 amount = depositAmount;

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        SwapParams memory swapParams = SwapParams({
            sellTokenAddress: address(baseAsset),
            sellAmount: amount,
            buyTokenAddress: WETH9_ADDRESS,
            buyAmount: amount,
            data: "", // no real payload since the swap is mocked
            extraData: ""
        });

        uint256 wethBalanceBefore = IERC20(WETH9_ADDRESS).balanceOf(address(this));

        bytes[] memory calls = new bytes[](3);

        autoPool.approve(address(autoPoolRouter), type(uint256).max);
        calls[0] =
            abi.encodeCall(autoPoolRouter.withdraw, (autoPool, address(autoPoolRouter), amount, type(uint256).max));
        calls[1] = abi.encodeCall(autoPoolRouter.swapToken, (address(swapperMock), swapParams));
        calls[2] = abi.encodeCall(autoPoolRouter.sweepToken, (IERC20(WETH9_ADDRESS), 1, address(this)));

        autoPoolRouter.multicall(calls);

        uint256 wethBalanceAfter = IERC20(WETH9_ADDRESS).balanceOf(address(this));

        assertGt(wethBalanceAfter, wethBalanceBefore);
    }

    function test_redeem() public {
        uint256 amount = depositAmount; // TODO: fuzz

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        // -- try to fail slippage first by requesting a little more assets than we can get-- //
        autoPool.approve(address(autoPoolRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinAmountError.selector));
        autoPoolRouter.redeem(autoPool, address(this), amount, amount + 1);

        // -- now test a successful redeem -- //
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = autoPool.balanceOf(address(this));

        // TODO: test eth unwrap!!
        autoPool.approve(address(autoPoolRouter), sharesBefore);
        uint256 assetsReceived = autoPoolRouter.redeem(autoPool, address(this), amount, amount);

        assertEq(assetsReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore + assetsReceived);
        assertEq(autoPool.balanceOf(address(this)), sharesBefore - amount);
    }

    function test_redeemToDeposit() public {
        uint256 amount = depositAmount;
        autoPool2 = _setupVault("vault2");

        // do deposit to vault #1 first
        uint256 sharesReceived = _deposit(autoPool, amount);

        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));

        // -- try to fail slippage first -- //
        autoPool.approve(address(autoPoolRouter), amount);
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinSharesError.selector));
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

    function test_redeemMax() public {
        uint256 amount = depositAmount;

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        uint256 sharesBefore = autoPool.balanceOf(address(this));

        autoPool.approve(address(autoPoolRouter), sharesBefore);

        //Try to fail with an invalid minAmountOut
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinAmountError.selector));
        uint256 amountOut = autoPoolRouter.redeemMax(autoPool, address(this), amount + 1);

        //Do the actual redeem
        amountOut = autoPoolRouter.redeemMax(autoPool, address(this), amount);
        uint256 sharesAfter = autoPool.balanceOf(address(this));

        assertEq(amountOut, amount);
        assertEq(sharesAfter, 0);
    }

    function test_redeemMax_lessMinAmountOut() public {
        uint256 amount = depositAmount;

        // deposit first
        baseAsset.approve(address(autoPoolRouter), amount);
        _deposit(autoPool, amount);

        uint256 sharesBefore = autoPool.balanceOf(address(this));

        autoPool.approve(address(autoPoolRouter), sharesBefore);

        //Try to fail with an invalid minAmountOut
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinAmountError.selector));
        uint256 amountOut = autoPoolRouter.redeemMax(autoPool, address(this), amount + 1);

        //Do the actual redeem
        amountOut = autoPoolRouter.redeemMax(autoPool, address(this), 0);
        uint256 sharesAfter = autoPool.balanceOf(address(this));

        assertEq(amountOut, amount);
        assertEq(sharesAfter, 0);
    }

    function test_withdrawToDeposit() public {
        uint256 amount = depositAmount;
        autoPool2 = _setupVault("vault2");

        // do deposit to vault #1 first
        uint256 sharesReceived = _deposit(autoPool, amount);

        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));

        uint256 minSharesExpected = autoPool2.previewDeposit(amount);

        // -- try to fail slippage first -- //
        autoPool.approve(address(autoPoolRouter), sharesReceived);
        vm.expectRevert(abi.encodeWithSelector(IAutopilotRouterBase.MinSharesError.selector));
        autoPoolRouter.withdrawToDeposit(
            autoPool, autoPool2, address(this), amount, sharesReceived, minSharesExpected + 1
        );

        // -- now try a successful withdrawToDeposit scenario -- //

        // Do actual `withdrawToDeposit` call
        uint256 newSharesReceived = autoPoolRouter.withdrawToDeposit(
            autoPool, autoPool2, address(this), amount, sharesReceived, minSharesExpected
        );

        // Check final state
        assertEq(newSharesReceived, amount);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore, "Base asset amount should not change");
        assertEq(autoPool.balanceOf(address(this)), 0, "Shares in vault #1 should be 0 after the move");
        assertEq(autoPool2.balanceOf(address(this)), newSharesReceived, "Shares in vault #2 should be increased");
    }

    // All three rewarder based functions use same path to check for valid vault, use stake to test all.
    function test_RevertsOnInvalidVault() public {
        // No need to approve, deposit to vault, etc, revert will happen before transfer.
        vm.expectRevert(Errors.ItemNotFound.selector);
        autoPoolRouter.stakeVaultToken(IERC20(makeAddr("NOT_Autopool_VAULT")), depositAmount);
    }

    function test_stakeVaultToken_Router() public {
        // Get reward and vault balances of `address(this)` before.
        uint256 shareBalanceBefore = _deposit(autoPool, depositAmount);
        uint256 stakedBalanceBefore = autoPoolRewarder.balanceOf(address(this));
        uint256 rewarderShareBalanceBefore = autoPool.balanceOf(address(autoPoolRewarder));

        // Checks pre stake.
        assertEq(shareBalanceBefore, depositAmount); // First deposit, no supply yet, mints 1:1.
        assertEq(stakedBalanceBefore, 0); // User has not staked yet.
        assertEq(rewarderShareBalanceBefore, 0); // Nothing in rewarder yet.

        // Approve rewarder and stake via router.
        autoPool.approve(address(autoPoolRouter), shareBalanceBefore);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shareBalanceBefore, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shareBalanceBefore));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shareBalanceBefore));

        autoPoolRouter.multicall(calls);

        // Reward and balances of `address(this)` after stake.
        uint256 shareBalanceAfter = autoPool.balanceOf(address(this));
        uint256 stakedBalanceAfter = autoPoolRewarder.balanceOf(address(this));
        uint256 rewarderShareBalanceAfter = autoPool.balanceOf(address(autoPoolRewarder));

        // Post stake checks.
        assertEq(shareBalanceAfter, 0); // All shares should be staked.
        assertEq(stakedBalanceAfter, shareBalanceBefore); // Staked balance should be 1:1 shares.
        assertEq(rewarderShareBalanceAfter, shareBalanceBefore); // Should own all shares.
    }

    function test_RevertRewarderDoesNotExist_withdraw() public {
        // Doesn't need to stake first, checks before actual withdrawal
        vm.expectRevert(Errors.ItemNotFound.selector);
        autoPoolRouter.withdrawVaultToken(autoPool, IMainRewarder(makeAddr("FAKE_REWARDER")), 1, false);
    }

    function test_WithdrawFromPastRewarder() public {
        // Deposit, approve, stake.
        uint256 shareBalanceBefore = _deposit(autoPool, depositAmount);
        autoPool.approve(address(autoPoolRouter), shareBalanceBefore);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shareBalanceBefore, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shareBalanceBefore));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shareBalanceBefore));

        autoPoolRouter.multicall(calls);

        // Replace rewarder.
        address newRewarder = address(
            new AutopoolMainRewarder(
                systemRegistry, address(new MockERC20("X", "X", 18)), 1000, 1000, true, address(autoPool)
            )
        );
        vm.mockCall(
            address(accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.AUTO_POOL_REWARD_MANAGER, address(this)),
            abi.encode(true)
        );
        autoPool.setRewarder(newRewarder);

        // Make sure correct rewarder set.
        assertEq(address(autoPool.rewarder()), newRewarder);
        assertTrue(autoPool.isPastRewarder(address(autoPoolRewarder)));

        uint256 userBalanceInPastRewarderBefore = autoPoolRewarder.balanceOf(address(this));
        uint256 userBalanceAutopoolTokenBefore = autoPool.balanceOf(address(this));

        assertEq(userBalanceInPastRewarderBefore, shareBalanceBefore);
        assertEq(userBalanceAutopoolTokenBefore, 0);

        // Fake rewarder - 0x002C41f924b4f3c0EE3B65749c4481f7cc9Dea03
        // Real rewarder - 0xc1A7C52ED8c7671a56e8626e7ae362334480f599

        autoPoolRouter.withdrawVaultToken(autoPool, autoPoolRewarder, shareBalanceBefore, false);

        uint256 userBalanceInPastRewarderAfter = autoPoolRewarder.balanceOf(address(this));
        uint256 userBalanceAutopoolTokenAfter = autoPool.balanceOf(address(this));

        assertEq(userBalanceInPastRewarderAfter, 0);
        assertEq(userBalanceAutopoolTokenAfter, shareBalanceBefore);
    }

    function test_withdrawVaultToken_NoClaim_Router() public {
        // Stake first.
        uint256 shareBalanceBefore = _deposit(autoPool, depositAmount);
        // Stake to rewarder.
        autoPool.approve(address(autoPoolRouter), shareBalanceBefore);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shareBalanceBefore, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shareBalanceBefore));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shareBalanceBefore));

        autoPoolRouter.multicall(calls);

        // Make sure balances match expected.
        assertEq(autoPool.balanceOf(address(this)), 0); // All shares transferred out.
        assertEq(autoPool.balanceOf(address(autoPoolRewarder)), shareBalanceBefore); // All shares owned by rewarder.
        assertEq(autoPoolRewarder.balanceOf(address(this)), shareBalanceBefore); // Should mint 1:1 for shares.

        // Withdraw half of shares.
        autoPoolRouter.withdrawVaultToken(autoPool, autoPoolRewarder, shareBalanceBefore, false);

        assertEq(autoPool.balanceOf(address(this)), shareBalanceBefore); // All shares should be returned to user.
        assertEq(autoPool.balanceOf(address(autoPoolRewarder)), 0); // All shares transferred out.
        assertEq(autoPoolRewarder.balanceOf(address(this)), 0); // Balance should be properly adjusted.
    }

    function test_withdrawVaultToken_Claim_Router() public {
        uint256 localStakeAmount = 1000;

        // Grant liquidator role to treasury to allow queueing of Toke rewards.
        // Neccessary because rewarder uses Toke as reward token.
        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, TREASURY);

        // Make sure Toke is not going to be sent to GPToke contract.
        assertEq(autoPoolRewarder.tokeLockDuration(), 0);

        // Prank treasury to approve rewarder and queue toke rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(autoPoolRewarder), localStakeAmount);
        autoPoolRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to Autopool.
        uint256 sharesReceived = _deposit(autoPool, depositAmount);

        // Stake Autopool
        autoPool.approve(address(autoPoolRouter), sharesReceived);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, sharesReceived, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), sharesReceived));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, sharesReceived));

        autoPoolRouter.multicall(calls);

        // Snapshot values before withdraw.
        uint256 stakeBalanceBefore = autoPoolRewarder.balanceOf(address(this));
        uint256 shareBalanceBefore = autoPool.balanceOf(address(this));
        uint256 rewarderBalanceRewardTokenBefore = toke.balanceOf(address(autoPoolRewarder));
        uint256 userBalanceRewardTokenBefore = toke.balanceOf(address(this));

        assertEq(stakeBalanceBefore, sharesReceived); // Amount staked should be total shares minted.
        assertEq(shareBalanceBefore, 0); // User should have transferred all assets out.
        assertEq(rewarderBalanceRewardTokenBefore, localStakeAmount); // All reward should still be in rewarder.
        assertEq(userBalanceRewardTokenBefore, 0); // User should have no reward token before withdrawal.

        // Roll for entire reward duration, gives all rewards to user.  100 is reward duration.
        vm.roll(block.number + 100);

        // Unstake.
        autoPoolRouter.withdrawVaultToken(autoPool, autoPoolRewarder, depositAmount, true);

        // Snapshot balances after withdrawal.
        uint256 stakeBalanceAfter = autoPoolRewarder.balanceOf(address(this));
        uint256 shareBalanceAfter = autoPool.balanceOf(address(this));
        uint256 rewarderBalanceRewardTokenAfter = toke.balanceOf(address(autoPoolRewarder));
        uint256 userBalanceRewardTokenAfter = toke.balanceOf(address(this));

        assertEq(stakeBalanceAfter, 0); // All should be unstaked for user.
        assertEq(shareBalanceAfter, depositAmount); // All shares should be returned to user.
        assertEq(rewarderBalanceRewardTokenAfter, 0); // All should be transferred to user.
        assertEq(userBalanceRewardTokenAfter, localStakeAmount); // User should now own all reward tokens.
    }

    function test_RevertRewarderDoesNotExist_claim() public {
        vm.expectRevert(Errors.ItemNotFound.selector);
        autoPoolRouter.claimAutopoolRewards(autoPool, IMainRewarder(makeAddr("FAKE_REWARDER")));
    }

    function test_ClaimFromPastRewarder() public {
        uint256 localStakeAmount = 1000;

        // Grant treasury liquidator role, allows queueing of rewards.
        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, TREASURY);

        // Check Toke lock duration.
        assertEq(autoPoolRewarder.tokeLockDuration(), 0);

        // Prank treasury, queue rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(autoPoolRewarder), localStakeAmount);
        autoPoolRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to vault.
        uint256 sharesReceived = _deposit(autoPool, depositAmount);

        // Stake to rewarder.
        autoPool.approve(address(autoPoolRouter), sharesReceived);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, sharesReceived, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), sharesReceived));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, sharesReceived));

        autoPoolRouter.multicall(calls);

        // Roll block for reward claiming.
        vm.roll(block.number + 100);

        // Create new rewarder, set as rewarder on Autopool vault.
        AutopoolMainRewarder newRewarder = new AutopoolMainRewarder(
            systemRegistry, address(new MockERC20("X", "X", 18)), 100, 100, false, address(autoPool)
        );
        vm.mockCall(
            address(accessController),
            abi.encodeWithSignature("hasRole(bytes32,address)", Roles.AUTO_POOL_REWARD_MANAGER, address(this)),
            abi.encode(true)
        );
        autoPool.setRewarder(address(newRewarder));

        // Make sure rewarder set as past.
        assertTrue(autoPool.isPastRewarder(address(autoPoolRewarder)));

        // Snapshot and checks.
        uint256 userRewardsPastRewarderBefore = autoPoolRewarder.earned(address(this));
        uint256 userRewardTokenBalanceBefore = toke.balanceOf(address(this));
        assertEq(userRewardsPastRewarderBefore, localStakeAmount);

        // Claim rewards.
        autoPoolRouter.claimAutopoolRewards(autoPool, autoPoolRewarder);

        // Snapshot and checks.
        uint256 userClaimedRewards = toke.balanceOf(address(this));
        assertEq(userRewardTokenBalanceBefore + userClaimedRewards, localStakeAmount);
    }

    function test_wrapETH9_Parameterized() public {
        vm.deal(address(autoPoolRouter), 2 ether);

        assertEq(address(autoPoolRouter).balance, 2 ether);

        vm.expectRevert(PeripheryPayments.InsufficientETH.selector);
        autoPoolRouter.wrapWETH9(3 ether);

        autoPoolRouter.wrapWETH9(1 ether);

        assertEq(weth.balanceOf(address(autoPoolRouter)), 1 ether);
        assertEq(address(autoPoolRouter).balance, 1 ether);
    }

    function test_wrapETH9_All() public {
        vm.deal(address(autoPoolRouter), 1 ether);

        assertEq(address(autoPoolRouter).balance, 1 ether);
        assertEq(weth.balanceOf(address(autoPoolRouter)), 0);

        autoPoolRouter.wrapWETH9();

        assertEq(address(autoPoolRouter).balance, 0);
        assertEq(weth.balanceOf(address(autoPoolRouter)), 1 ether);

        autoPoolRouter.wrapWETH9{ value: 1 ether }();

        assertEq(address(autoPoolRouter).balance, 0);
        assertEq(weth.balanceOf(address(autoPoolRouter)), 2 ether);
    }

    function test_unwrapWETH9() public {
        vm.deal(address(autoPoolRouter), 1 ether);
        autoPoolRouter.wrapWETH9();

        assertEq(weth.balanceOf(address(autoPoolRouter)), 1 ether);

        vm.expectRevert(PeripheryPayments.InsufficientWETH9.selector);
        autoPoolRouter.unwrapWETH9(100 ether, address(autoPoolRouter));

        autoPoolRouter.unwrapWETH9(1 ether, address(autoPoolRouter));

        assertEq(address(autoPoolRouter).balance, 1 ether);

        vm.deal(address(autoPoolRouter), 1 ether);
        autoPoolRouter.wrapWETH9();

        autoPoolRouter.unwrapWETH9(1 ether, address(99));

        assertEq(address(99).balance, 1 ether);
    }

    function test_refundETH() public {
        vm.deal(address(autoPoolRouter), 1 ether);

        assertEq(address(99).balance, 0);
        vm.startPrank(address(99));
        autoPoolRouter.refundETH();
        assertEq(address(99).balance, 1 ether);
        vm.stopPrank();
    }

    function test_claimRewards_Router() public {
        uint256 localStakeAmount = 1000;

        // Grant liquidator role to treasury to allow queueing of Toke rewards.
        // Neccessary because rewarder uses Toke as reward token.
        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, TREASURY);

        // Make sure Toke is not going to be sent to GPToke contract.
        assertEq(autoPoolRewarder.tokeLockDuration(), 0);

        // Prank treasury to approve rewarder and queue toke rewards.
        vm.startPrank(TREASURY);
        toke.approve(address(autoPoolRewarder), localStakeAmount);
        autoPoolRewarder.queueNewRewards(localStakeAmount);
        vm.stopPrank();

        // Deposit to Autopool.
        uint256 sharesReceived = _deposit(autoPool, depositAmount);

        // Stake Autopool
        autoPool.approve(address(autoPoolRouter), sharesReceived);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, sharesReceived, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), sharesReceived));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, sharesReceived));

        autoPoolRouter.multicall(calls);

        assertEq(toke.balanceOf(address(this)), 0); // Make sure no Toke for user before claim.
        assertEq(toke.balanceOf(address(autoPoolRewarder)), localStakeAmount); // Rewarder has proper amount before
        // claim.

        // Roll for entire reward duration, gives all rewards to user.  100 is reward duration.
        vm.roll(block.number + 100);

        autoPoolRouter.claimAutopoolRewards(autoPool, autoPoolRewarder);

        assertEq(toke.balanceOf(address(this)), localStakeAmount); // Make sure all toke transferred to user.
        assertEq(toke.balanceOf(address(autoPoolRewarder)), 0); // Rewarder should have no toke left.
    }

    function test_DepositAndStakeMulticall() public {
        // Approve router, rewarder. Max approvals to make it easier.
        baseAsset.approve(address(autoPoolRouter), type(uint256).max);
        autoPool.approve(address(autoPoolRouter), type(uint256).max);

        // Get preview of shares for staking.
        uint256 expectedShares = autoPool.previewDeposit(depositAmount);

        bytes[] memory calls = new bytes[](5);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, depositAmount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), depositAmount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(autoPoolRouter), depositAmount, 0));
        calls[3] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), expectedShares));
        calls[4] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (IERC20(address(autoPool)), expectedShares));

        // Snapshot balances for user (address(this)) before multicall.
        uint256 baseAssetBalanceBefore = baseAsset.balanceOf(address(this));
        uint256 shareBalanceBefore = autoPool.balanceOf(address(this));
        uint256 rewardBalanceBefore = autoPoolRewarder.balanceOf(address(this));

        // Check snapshots.
        assertGe(baseAssetBalanceBefore, depositAmount); // Make sure there is at least enough to deposit.
        assertEq(shareBalanceBefore, 0); // No deposit, should be zero.
        assertEq(rewardBalanceBefore, 0); // No rewards yet, should be zero.

        // Execute multicall.
        autoPoolRouter.multicall(calls);

        // Snapshot balances after.
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 shareBalanceAfter = autoPool.balanceOf(address(this));
        uint256 rewardBalanceAfter = autoPoolRewarder.balanceOf(address(this));

        assertEq(baseAssetBalanceBefore - depositAmount, baseAssetBalanceAfter); // Only `depositAmount` taken out.
        assertEq(shareBalanceAfter, 0); // Still zero, all shares should have been moved.
        assertEq(rewardBalanceAfter, expectedShares); // Should transfer 1:1.
    }

    function test_withdrawStakeAndWithdrawMulticall() public {
        // Deposit and stake normally.
        baseAsset.approve(address(autoPoolRouter), depositAmount);
        uint256 shares = _deposit(autoPool, depositAmount);
        autoPool.approve(address(autoPoolRouter), shares);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shares, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shares));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shares));

        autoPoolRouter.multicall(calls);

        // Need array of bytes with two members, one for unstaking from rewarder, other for withdrawing from Autopool.
        bytes[] memory data = new bytes[](2);

        // Approve router to burn share tokens.
        autoPool.approve(address(autoPoolRouter), shares);

        // Generate data.
        uint256 rewardBalanceBefore = autoPoolRewarder.balanceOf(address(this));
        data[0] = abi.encodeWithSelector(
            autoPoolRouter.withdrawVaultToken.selector, autoPool, autoPoolRewarder, rewardBalanceBefore, false
        );
        data[1] = abi.encodeWithSelector(
            autoPoolRouter.redeem.selector, autoPool, address(this), rewardBalanceBefore, 1, false
        );

        // Snapshot balances for `address(this)` before call.
        uint256 baseAssetBalanceBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBalanceBefore = autoPool.balanceOf(address(this));

        // Check snapshots.  Don't check baseAsset balance here, check after multicall to make sure correct amount
        // comes back.
        assertEq(rewardBalanceBefore, shares); // All shares minted should be in rewarder.
        assertEq(sharesBalanceBefore, 0); // User should own no shares.

        // Execute multicall.
        autoPoolRouter.multicall(data);

        // Post multicall snapshot.
        uint256 rewardBalanceAfter = autoPoolRewarder.balanceOf(address(this));
        uint256 baseAssetBalanceAfter = baseAsset.balanceOf(address(this));
        uint256 sharesBalanceAfter = autoPool.balanceOf(address(this));

        assertEq(rewardBalanceAfter, 0); // All rewards removed.
        assertEq(baseAssetBalanceAfter, baseAssetBalanceBefore + depositAmount); // Should have all base asset back.
        assertEq(sharesBalanceAfter, 0); // All shares burned.
    }

    function test_catchCustomErrors() public {
        AutopilotRouterWrapper router = new AutopilotRouterWrapper(systemRegistry);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(AutopilotRouterWrapper.doSomethingRight.selector);
        data[1] = abi.encodeWithSelector(AutopilotRouterWrapper.doSomethingWrong.selector);

        vm.expectRevert(AutopilotRouterWrapper.SomethingWentWrong.selector);
        router.multicall(data);
    }

    function test_stakeWorksWith_MaxAmountGreaterThanUserBalance() public {
        baseAsset.approve(address(autoPoolRouter), depositAmount);
        uint256 shares = _deposit(autoPool, depositAmount);

        autoPool.approve(address(autoPoolRouter), type(uint256).max);

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shares, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shares));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shares));

        autoPoolRouter.multicall(calls);

        // Should only deposit amount of shares user has.
        assertEq(autoPoolRewarder.balanceOf(address(this)), shares);
    }

    function test_withdrawWorksWith_MaxAmountGreaterThanUsersBalance() public {
        baseAsset.approve(address(autoPoolRouter), depositAmount);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, depositAmount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), depositAmount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), depositAmount, 1));

        bytes[] memory results = autoPoolRouter.multicall(calls);

        uint256 shares = abi.decode(results[2], (uint256));

        autoPool.approve(address(autoPoolRouter), shares);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (autoPool, shares, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (autoPool, address(autoPoolRewarder), shares));
        calls[2] = abi.encodeCall(autoPoolRouter.stakeVaultToken, (autoPool, shares));

        results = autoPoolRouter.multicall(calls);

        autoPoolRouter.withdrawVaultToken(autoPool, autoPoolRewarder, type(uint256).max, false);

        assertEq(autoPool.balanceOf(address(this)), shares);
    }

    /* **************************************************************************** */
    /* 				    	    	Helper methods									*/

    function _deposit(AutopoolETH _autoPool, uint256 amount) private returns (uint256 sharesReceived) {
        uint256 baseAssetBefore = baseAsset.balanceOf(address(this));
        uint256 sharesBefore = _autoPool.balanceOf(address(this));

        baseAsset.approve(address(autoPoolRouter), amount);

        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeCall(autoPoolRouter.pullToken, (baseAsset, amount, address(autoPoolRouter)));
        calls[1] = abi.encodeCall(autoPoolRouter.approve, (baseAsset, address(autoPool), amount));
        calls[2] = abi.encodeCall(autoPoolRouter.deposit, (autoPool, address(this), amount, 0));

        bytes[] memory results = autoPoolRouter.multicall(calls);

        sharesReceived = abi.decode(results[2], (uint256));

        assertGt(sharesReceived, 0);
        assertEq(baseAsset.balanceOf(address(this)), baseAssetBefore - amount);
        assertEq(_autoPool.balanceOf(address(this)), sharesBefore + sharesReceived);
    }

    function _mint(AutopoolETH _autoPool, uint256 shares) private returns (uint256 assets) {
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
        autoPoolTemplate = address(new AutopoolETH(systemRegistry, address(weth)));
        autoPoolFactory = new AutopoolFactory(systemRegistry, autoPoolTemplate, 800, 100);
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        systemRegistry.setAutopoolFactory(VaultTypes.LST, address(autoPoolFactory));
        AutopoolETHStrategy stratTemplate = new AutopoolETHStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        autoPool = AutopoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256("weth"), autoPoolInitData
            )
        );
        assert(systemRegistry.autoPoolRegistry().isVault(address(autoPool)));
    }
}
