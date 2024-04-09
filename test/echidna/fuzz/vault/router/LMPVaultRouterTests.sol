// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

import { ILMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";
import { ISystemRegistry } from "src/vault/LMPVaultRouterBase.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";

import { hevm } from "test/echidna/fuzz/utils/Hevm.sol";
import { BasePoolSetup } from "test/echidna/fuzz/vault/BaseSetup.sol";
import { PropertiesAsserts } from "crytic/properties/contracts/util/PropertiesHelper.sol";

import { ERC2612 } from "test/utils/ERC2612.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";

contract TestRouter is LMPVaultRouter {
    using SafeERC20 for IERC20;

    constructor(ISystemRegistry _systemRegistry, address _weth9) LMPVaultRouter(_systemRegistry, _weth9) { }

    /// @notice Intentionally vulnerable. Will filter out for normal runs but used to test checks are working
    function pullTokenFrom(IERC20 token, uint256 amount, address from, address recipient) public payable {
        token.safeTransferFrom(from, recipient, amount);
    }
}

/// @dev Custom mocked swapper for testing to represent a 1:1 swap
contract SwapperMock is BaseAsyncSwapper {
    constructor(address _aggregator) BaseAsyncSwapper(_aggregator) { }

    function swap(SwapParams memory params) public override returns (uint256 buyTokenAmountReceived) {
        // Mock 1:1 swap
        TestERC20(params.buyTokenAddress).mint(address(this), params.buyAmount);
        return params.buyAmount;
    }
}

abstract contract LMPVaultRouterUsage is BasePoolSetup, PropertiesAsserts {
    TestERC20 internal _vaultAsset;
    TestRouter internal lmpVaultRouter;
    SwapperMock internal swapperMock;

    /// @dev The caller of the operation
    address[] internal _msgSenders;

    /// @dev The user shares balance at the beginning of the operation
    uint256[] internal _userSharesAtStarts;

    /// @dev The user asset balance at the beginning of the operation
    uint256[] internal _userAssetsAtStarts;

    /// @dev The user shares balance at the end of the operation
    uint256[] internal _userSharesAtEnds;

    /// @dev The user asset balance at the end of the operation
    uint256[] internal _userAssetsAtEnds;

    /// @dev queued calls that will get executed in a single multicall
    bytes[] internal queuedCalls;

    ///@dev modifier to help track User 1 shares on
    modifier updateUser1Balance() {
        _msgSenders.push(msg.sender);
        _userSharesAtStarts.push(_pool.balanceOf(_user1));
        _userAssetsAtStarts.push(_vaultAsset.balanceOf(_user1));
        _;
        _userSharesAtEnds.push(_pool.balanceOf(_user1));
        _userAssetsAtEnds.push(_vaultAsset.balanceOf(_user1));
    }

    constructor() BasePoolSetup() {
        _vaultAsset = new TestERC20("vaultAsset", "vaultAsset");
        _vaultAsset.setDecimals(18);
        initializeBaseSetup(address(_vaultAsset));

        _pool.initialize(address(_strategy), "SYMBOL", "NAME", abi.encode(""));
        _pool.setDisableNavDecreaseCheck(true);
        _pool.setCryticFnsEnabled(false);

        lmpVaultRouter = new TestRouter(_systemRegistry, address(_weth));

        _pool.toggleAllowedUser(address(this));
        _pool.toggleAllowedUser(_user1);
        _pool.toggleAllowedUser(_user2);
        _pool.toggleAllowedUser(_user3);
        _pool.toggleAllowedUser(address(lmpVaultRouter));

        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(_systemRegistry);
        _systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        swapperMock = new SwapperMock(address(123));
        asyncSwapperRegistry.register(address(swapperMock));
    }

    // Multicall
    function executeMulticall() public updateUser1Balance {
        _startPrank(msg.sender);
        lmpVaultRouter.multicall(queuedCalls);
        _stopPrank();

        delete queuedCalls;
    }

    // Approve
    function approveAssetsToRouter(uint256 amount) public updateUser1Balance {
        _startPrank(msg.sender);
        _vaultAsset.approve(address(lmpVaultRouter), amount);
        _stopPrank();
    }

    function approveSharesToRouter(uint256 amount) public updateUser1Balance {
        _startPrank(msg.sender);
        _pool.approve(address(lmpVaultRouter), amount);
        _stopPrank();
    }

    function approveAsset(uint256 toSeed, uint256 amount) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.approve(_vaultAsset, to, amount);
        _stopPrank();
    }

    function queueApproveAsset(uint256 toSeed, uint256 amount) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.approve.selector, _vaultAsset, to, amount));
    }

    function approveShare(uint256 toSeed, uint256 amount) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.approve(_pool, to, amount);
        _stopPrank();
    }

    function queueApproveShare(uint256 toSeed, uint256 amount) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.approve.selector, _pool, to, amount));
    }

    // Mint
    function mintAssets(uint256 mintToSeed, uint256 amountSeed) public updateUser1Balance {
        address mintTo = _resolveUserFromSeed(mintToSeed);
        uint256 amount = clampBetween(amountSeed, 1e18, 1000e18);

        _vaultAsset.mint(mintTo, amount);
    }

    function mint(uint256 toSeed, uint256 shares, uint256 maxAmountIn) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.mint(_pool, to, shares, maxAmountIn);
        _stopPrank();
    }

    function queueMint(uint256 toSeed, uint256 shares, uint256 maxAmountIn) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);
        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.mint.selector, _pool, to, shares, maxAmountIn));
    }

    // Deposit
    function deposit(uint256 toSeed, uint256 amount, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.deposit(_pool, to, amount, minSharesOut);
        _stopPrank();
    }

    function queueDeposit(uint256 toSeed, uint256 amount, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);
        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.deposit.selector, _pool, to, amount, minSharesOut));
    }

    function depositMax(uint256 toSeed, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.depositMax(_pool, to, minSharesOut);
        _stopPrank();
    }

    function queueDepositMax(uint256 toSeed, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.depositMax.selector, _pool, to, minSharesOut));
    }

    // Permit
    function permit(uint256 userSeed, uint256 senderSeed, uint256 amount) public updateUser1Balance {
        address user = _resolveUserFromSeed(userSeed);
        address sender = _resolveUserFromSeed(senderSeed);
        uint256 signerKey = _resolveUserPrivateKeyFromSeed(userSeed);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            _pool.DOMAIN_SEPARATOR(), signerKey, user, address(lmpVaultRouter), amount, 0, deadline
        );

        _startPrank(sender);
        lmpVaultRouter.selfPermit(address(_pool), amount, deadline, v, r, s);
        _stopPrank();
    }

    function queuePermit(uint256 userSeed, uint256 amount) public updateUser1Balance {
        address user = _resolveUserFromSeed(userSeed);
        uint256 signerKey = _resolveUserPrivateKeyFromSeed(userSeed);

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            _pool.DOMAIN_SEPARATOR(), signerKey, user, address(lmpVaultRouter), amount, 0, deadline
        );

        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.selfPermit.selector, address(_pool), amount, deadline, v, r, s)
        );
    }

    // Pull

    /// @dev This is vulnerable and is filtered function. Use it verify checks are working
    function pullTokenFromAsset(uint256 fromSeed, uint256 amount, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);
        address from = _resolveUserFromSeed(fromSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.pullTokenFrom(_vaultAsset, amount, from, recipient);
        _stopPrank();
    }

    /// @dev This is vulnerable and is filtered function. Use it verify checks are working
    function queuePullTokenFromAsset(
        uint256 fromSeed,
        uint256 amount,
        uint256 recipientSeed
    ) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);
        address from = _resolveUserFromSeed(fromSeed);

        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.pullTokenFrom.selector, _vaultAsset, amount, from, recipient)
        );
    }

    function pullTokenAsset(uint256 amount, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.pullToken(_vaultAsset, amount, recipient);
        _stopPrank();
    }

    function queuePullTokenAsset(uint256 amount, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.pullToken.selector, _vaultAsset, amount, recipient));
    }

    function pullTokenShare(uint256 amount, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.pullToken(_pool, amount, recipient);
        _stopPrank();
    }

    function queuePullTokenShare(uint256 amount, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.pullToken.selector, _pool, amount, recipient));
    }

    function pullTokenAssetToRouter(uint256 amount) public updateUser1Balance {
        _startPrank(msg.sender);
        lmpVaultRouter.pullToken(_vaultAsset, amount, address(lmpVaultRouter));
        _stopPrank();
    }

    function queuePullTokenAssetToRouter(uint256 amount) public updateUser1Balance {
        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.pullToken.selector, _vaultAsset, amount, address(lmpVaultRouter))
        );
    }

    function pullTokenShareToRouter(uint256 amount) public updateUser1Balance {
        _startPrank(msg.sender);
        lmpVaultRouter.pullToken(_pool, amount, address(lmpVaultRouter));
        _stopPrank();
    }

    function queuePullTokenShareToRouter(uint256 amount) public updateUser1Balance {
        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.pullToken.selector, _pool, amount, address(lmpVaultRouter))
        );
    }

    // Sweep
    function sweepTokenAsset(uint256 amountMin, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.sweepToken(_vaultAsset, amountMin, recipient);
        _stopPrank();
    }

    function queueSweepTokenAsset(uint256 amountMin, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.sweepToken.selector, _vaultAsset, amountMin, recipient));
    }

    function sweepTokenShare(uint256 amountMin, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.sweepToken(_pool, amountMin, recipient);
        _stopPrank();
    }

    function queueSweepTokenShare(uint256 amountMin, uint256 recipientSeed) public updateUser1Balance {
        address recipient = _resolveUserFromSeed(recipientSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.sweepToken.selector, _pool, amountMin, recipient));
    }

    // Withdraw
    function withdraw(
        uint256 toSeed,
        uint256 amount,
        uint256 maxSharesOut,
        bool unwrapWETH
    ) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.withdraw(_pool, to, amount, maxSharesOut, unwrapWETH);
        _stopPrank();
    }

    function queueWithdraw(
        uint256 toSeed,
        uint256 amount,
        uint256 maxSharesOut,
        bool unwrapWETH
    ) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.withdraw.selector, _pool, to, amount, maxSharesOut, unwrapWETH)
        );
    }

    function withdrawToDeposit(
        uint256 toSeed,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.withdrawToDeposit(_pool, _pool, to, amount, maxSharesIn, minSharesOut);
        _stopPrank();
    }

    function queueWithdrawToDeposit(
        uint256 toSeed,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(
            abi.encodeWithSelector(
                lmpVaultRouter.withdrawToDeposit.selector, _pool, _pool, to, amount, maxSharesIn, minSharesOut
            )
        );
    }

    // Swap
    function swapAndDepositToVault(uint256 toSeed, uint256 amount, uint256 minSharesOut) public updateUser1Balance {
        // Selling WETH for Vault Asset
        SwapParams memory swapParams = SwapParams({
            sellTokenAddress: address(_weth),
            sellAmount: amount,
            buyTokenAddress: _pool.asset(),
            buyAmount: minSharesOut,
            data: "", // no real payload since the swap is mocked
            extraData: ""
        });

        address to = _resolveUserFromSeed(toSeed);

        // Mocked 1:1 swap
        _startPrank(msg.sender);

        lmpVaultRouter.swapAndDepositToVault(address(swapperMock), swapParams, _pool, to, minSharesOut);
        _stopPrank();
    }

    function queueSwapAndDepositToVault(
        uint256 toSeed,
        uint256 amount,
        uint256 minSharesOut
    ) public updateUser1Balance {
        // Selling WETH for Vault Asset
        SwapParams memory swapParams = SwapParams({
            sellTokenAddress: address(_weth),
            sellAmount: amount,
            buyTokenAddress: _pool.asset(),
            buyAmount: minSharesOut,
            data: "", // no real payload since the swap is mocked
            extraData: ""
        });

        address to = _resolveUserFromSeed(toSeed);

        // Mocked 1:1 swap
        queuedCalls.push(
            abi.encodeWithSelector(
                lmpVaultRouter.swapAndDepositToVault.selector, address(swapperMock), swapParams, _pool, to, minSharesOut
            )
        );
    }

    // Redeem
    function redeem(uint256 toSeed, uint256 shares, uint256 minAmountOut, bool unwrapWETH) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.redeem(_pool, to, shares, minAmountOut, unwrapWETH);
        _stopPrank();
    }

    function queueRedeem(
        uint256 toSeed,
        uint256 shares,
        uint256 minAmountOut,
        bool unwrapWETH
    ) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.redeem.selector, _pool, to, shares, minAmountOut, unwrapWETH)
        );
    }

    function redeemMax(uint256 toSeed, uint256 minAmountOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.redeemMax(_pool, to, minAmountOut);
        _stopPrank();
    }

    function queueRedeemMax(uint256 toSeed, uint256 minAmountOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(abi.encodeWithSelector(lmpVaultRouter.redeemMax.selector, _pool, to, minAmountOut));
    }

    ///@dev Anyone but User1 can try redeem to deposit
    function redeemToDeposit(uint256 toSeed, uint256 shares, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        _startPrank(msg.sender);
        lmpVaultRouter.redeemToDeposit(_pool, _pool, to, shares, minSharesOut);
        _stopPrank();
    }

    function queueRedeemToDeposit(uint256 toSeed, uint256 shares, uint256 minSharesOut) public updateUser1Balance {
        address to = _resolveUserFromSeed(toSeed);

        queuedCalls.push(
            abi.encodeWithSelector(lmpVaultRouter.redeemToDeposit.selector, _pool, _pool, to, shares, minSharesOut)
        );
    }

    // Utils
    function _startPrank(address user) internal virtual {
        hevm.prank(user);
    }

    function _stopPrank() internal virtual {
        // Intentionally blank. Have the pranks setup like this so that we can prank internally
        // to the test but also call from foundry test and not have it complain about starting
        // a prank while one is already in process
    }

    function _resolveUserFromSeed(uint256 userSeed) private returns (address) {
        uint256 userClamped = clampBetween(userSeed, 1, 3);
        address to = userClamped == 1 ? _user1 : userClamped == 2 ? _user2 : _user3;
        return to;
    }

    function _resolveUserPrivateKeyFromSeed(uint256 userSeed) private returns (uint256) {
        uint256 userClamped = clampBetween(userSeed, 1, 3);
        uint256 key = userClamped == 1 ? _user1PrivateKey : userClamped == 2 ? _user2PrivateKey : _user3PrivateKey;
        return key;
    }
}

// Echidna test
contract LMPVaultRouterTest is LMPVaultRouterUsage {
    constructor() LMPVaultRouterUsage() { }

    // Check that User 1 balances didn't change
    function echidna_only_user_initiated_tx_can_decrease_users_balances_through_router() public view returns (bool) {
        if (_msgSenders.length > 0) {
            for (uint256 i = 0; i < _msgSenders.length; i++) {
                if (_msgSenders[i] != _user1) {
                    if (_userSharesAtEnds[i] < _userSharesAtStarts[i]) {
                        return false;
                    }
                    if (_userAssetsAtEnds[i] < _userAssetsAtStarts[i]) {
                        return false;
                    }
                }
            }
        }

        return true;
    }
}
