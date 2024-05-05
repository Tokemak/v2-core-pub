// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { IAutoPool, IAutoPilotRouter } from "src/interfaces/vault/IAutoPilotRouter.sol";
import { IRewards } from "src/interfaces/rewarders/IRewards.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { AutoPilotRouterBase, ISystemRegistry } from "src/vault/AutoPilotRouterBase.sol";
import { Errors } from "src/utils/Errors.sol";

/// @title ERC4626Router contract
contract AutoPilotRouter is IAutoPilotRouter, AutoPilotRouterBase, ReentrancyGuard {
    using Address for address;

    constructor(ISystemRegistry _systemRegistry) AutoPilotRouterBase(_systemRegistry) { }

    // For the below, no approval needed, assumes vault is already max approved

    /// @inheritdoc IAutoPilotRouter
    function withdrawToDeposit(
        IAutoPool fromVault,
        IAutoPool toVault,
        address to,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) external override returns (uint256 sharesOut) {
        withdraw(fromVault, address(this), amount, maxSharesIn);
        approve(IERC20(toVault.asset()), address(toVault), amount);
        return deposit(toVault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutoPilotRouter
    function redeemToDeposit(
        IAutoPool fromVault,
        IAutoPool toVault,
        address to,
        uint256 shares,
        uint256 minSharesOut
    ) external override returns (uint256 sharesOut) {
        // amount out passes through so only one slippage check is needed
        uint256 amount = redeem(fromVault, address(this), shares, 0);

        approve(IERC20(toVault.asset()), address(toVault), amount);
        return deposit(toVault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutoPilotRouter
    function swapToken(
        address swapper,
        SwapParams memory swapParams
    ) external nonReentrant returns (uint256 amountReceived) {
        systemRegistry.asyncSwapperRegistry().verifyIsRegistered(swapper);

        bytes memory data = swapper.functionDelegateCall(
            abi.encodeWithSignature("swap((address,uint256,address,uint256,bytes,bytes))", swapParams), "SwapFailed"
        );

        amountReceived = abi.decode(data, (uint256));
    }

    /// @inheritdoc IAutoPilotRouter
    function depositBalance(
        IAutoPool vault,
        address to,
        uint256 minSharesOut
    ) public override returns (uint256 sharesOut) {
        uint256 vaultAssetBalance = IERC20(vault.asset()).balanceOf(address(this));
        approve(IERC20(vault.asset()), address(vault), vaultAssetBalance);
        return deposit(vault, to, vaultAssetBalance, minSharesOut);
    }

    /// @inheritdoc IAutoPilotRouter
    function depositMax(
        IAutoPool vault,
        address to,
        uint256 minSharesOut
    ) public override returns (uint256 sharesOut) {
        IERC20 asset = IERC20(vault.asset());
        uint256 assetBalance = asset.balanceOf(msg.sender);
        uint256 maxDeposit = vault.maxDeposit(to);
        uint256 amount = maxDeposit < assetBalance ? maxDeposit : assetBalance;
        pullToken(asset, amount, address(this));

        approve(IERC20(vault.asset()), address(vault), amount);
        return deposit(vault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutoPilotRouter
    function redeemMax(IAutoPool vault, address to, uint256 minAmountOut) public override returns (uint256 amountOut) {
        uint256 shareBalance = vault.balanceOf(msg.sender);
        uint256 maxRedeem = vault.maxRedeem(msg.sender);
        uint256 amountShares = maxRedeem < shareBalance ? maxRedeem : shareBalance;
        return redeem(vault, to, amountShares, minAmountOut);
    }

    /// @inheritdoc IAutoPilotRouter
    function claimRewards(
        IRewards rewarder,
        IRewards.Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override returns (uint256) {
        if (msg.sender != recipient.wallet) revert Errors.AccessDenied();
        return rewarder.claimFor(recipient, v, r, s);
    }
}
