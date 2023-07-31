// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20, SafeERC20, Address } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ILMPVault, ILMPVaultRouterBase } from "src/interfaces/vault/ILMPVaultRouterBase.sol";

import { SelfPermit } from "src/utils/SelfPermit.sol";
import { PeripheryPayments } from "src/utils/PeripheryPayments.sol";
import { Multicall } from "src/utils/Multicall.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

/// @title LMPVault Router Base Contract
abstract contract LMPVaultRouterBase is ILMPVaultRouterBase, SelfPermit, Multicall, PeripheryPayments {
    using SafeERC20 for IERC20;

    error InvalidAsset();
    error InvalidEthAmount(uint256 amountNeeded, uint256 amountSent);

    constructor(address _weth9) PeripheryPayments(IWETH9(_weth9)) { }

    /// @inheritdoc ILMPVaultRouterBase
    function mint(
        ILMPVault vault,
        address to,
        uint256 shares,
        uint256 maxAmountIn
    ) public payable virtual override returns (uint256 amountIn) {
        IERC20 vaultAsset = IERC20(vault.asset());
        uint256 assets = vault.previewMint(shares);

        if (msg.value > 0 && address(vaultAsset) == address(weth9)) {
            if (msg.value != assets) revert InvalidEthAmount(assets, msg.value);

            _processEthIn(vault);
        } else {
            pullToken(vaultAsset, assets, address(this));
        }

        vaultAsset.safeApprove(address(vault), assets);

        amountIn = vault.mint(shares, to);
        if (amountIn > maxAmountIn) {
            revert MaxAmountError();
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function deposit(
        ILMPVault vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    ) public payable virtual override returns (uint256 sharesOut) {
        IERC20 vaultAsset = IERC20(vault.asset());

        if (msg.value > 0 && address(vaultAsset) == address(weth9)) {
            if (msg.value != amount) revert InvalidEthAmount(amount, msg.value);

            _processEthIn(vault);
        } else {
            pullToken(vaultAsset, amount, address(this));
        }

        return _deposit(vault, to, amount, minSharesOut);
    }

    /// @dev Assumes tokens are already in the router
    function _deposit(
        ILMPVault vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    ) internal returns (uint256 sharesOut) {
        approve(IERC20(vault.asset()), address(vault), amount);
        if ((sharesOut = vault.deposit(amount, to)) < minSharesOut) {
            revert MinSharesError();
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function withdraw(
        ILMPVault vault,
        address to,
        uint256 amount,
        uint256 maxSharesOut,
        bool unwrapWETH
    ) public virtual override returns (uint256 sharesOut) {
        address destination = unwrapWETH ? address(this) : to;

        sharesOut = vault.withdraw(amount, destination, msg.sender);
        if (sharesOut > maxSharesOut) {
            revert MaxSharesError();
        }

        if (unwrapWETH) {
            _processWethOut(to);
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function redeem(
        ILMPVault vault,
        address to,
        uint256 shares,
        uint256 minAmountOut,
        bool unwrapWETH
    ) public virtual override returns (uint256 amountOut) {
        address destination = unwrapWETH ? address(this) : to;

        if ((amountOut = vault.redeem(shares, destination, msg.sender)) < minAmountOut) {
            revert MinAmountError();
        }

        if (unwrapWETH) {
            _processWethOut(to);
        }
    }

    function _processEthIn(ILMPVault vault) internal {
        // if asset is not weth, revert
        if (address(vault.asset()) != address(weth9)) {
            revert InvalidAsset();
        }

        // wrap eth
        weth9.deposit{ value: msg.value }();
    }

    function _processWethOut(address to) internal {
        uint256 balanceWETH9 = weth9.balanceOf(address(this));

        if (balanceWETH9 > 0) {
            weth9.withdraw(balanceWETH9);
            Address.sendValue(payable(to), balanceWETH9);
        }
    }
}
