// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20, SafeERC20, Address } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ILMPVault, ILMPVaultRouterBase } from "src/interfaces/vault/ILMPVaultRouterBase.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { LibAdapter } from "src/libs/LibAdapter.sol";
import { SelfPermit } from "src/utils/SelfPermit.sol";
import { PeripheryPayments } from "src/utils/PeripheryPayments.sol";
import { Multicall } from "src/utils/Multicall.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

/// @title LMPVault Router Base Contract
abstract contract LMPVaultRouterBase is
    ILMPVaultRouterBase,
    SelfPermit,
    Multicall,
    PeripheryPayments,
    SystemComponent
{
    using SafeERC20 for IERC20;

    constructor(
        address _weth9,
        ISystemRegistry _systemRegistry
    ) PeripheryPayments(IWETH9(_weth9)) SystemComponent(_systemRegistry) { }

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
            // We allow different amounts for different functions while performing a multicall now
            // and msg.value can be more than a single instructions amount
            // so we don't verify msg.value == assets
            _processEthIn(assets);
        } else {
            pullToken(vaultAsset, assets, address(this));
        }
        LibAdapter._approve(vaultAsset, address(vault), assets);

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
            // We allow different amounts for different functions while performing a multicall now
            // and msg.value can be more than a single instructions amount
            // so we don't verify msg.value == amount
            _processEthIn(amount);
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
    ) public payable virtual override returns (uint256 sharesOut) {
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
    ) public payable virtual override returns (uint256 amountOut) {
        address destination = unwrapWETH ? address(this) : to;

        if ((amountOut = vault.redeem(shares, destination, msg.sender)) < minAmountOut) {
            revert MinAmountError();
        }

        if (unwrapWETH) {
            _processWethOut(to);
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function stakeVaultToken(address vaultToken, uint256 amount) external {
        IMainRewarder lmpRewarder = _checkVaultAndReturnRewarder(vaultToken);

        lmpRewarder.stake(msg.sender, amount);
    }

    /// @inheritdoc ILMPVaultRouterBase
    function unstakeVaultToken(address vaultToken, uint256 amount, bool claim) external {
        IMainRewarder lmpRewarder = _checkVaultAndReturnRewarder(vaultToken);

        lmpRewarder.withdraw(msg.sender, amount, claim);
    }

    /// @inheritdoc ILMPVaultRouterBase
    function claimRewards(address vaultToken) external {
        IMainRewarder lmpRewarder = _checkVaultAndReturnRewarder(vaultToken);

        // Always claims any extra rewards that exist.
        lmpRewarder.getReward(msg.sender, true);
    }

    ///@dev Function assumes that vault.asset() is verified externally to be weth9
    function _processEthIn(uint256 amount) internal {
        if (amount > 0) {
            // wrap eth
            weth9.deposit{ value: amount }();
        }
    }

    function _processWethOut(address to) internal {
        uint256 balanceWETH9 = weth9.balanceOf(address(this));

        if (balanceWETH9 > 0) {
            weth9.withdraw(balanceWETH9);
            Address.sendValue(payable(to), balanceWETH9);
        }
    }

    // Helper function for repeat functionalities.
    function _checkVaultAndReturnRewarder(address vault) internal returns (IMainRewarder) {
        if (!systemRegistry.lmpVaultRegistry().isVault(vault)) {
            revert Errors.ItemNotFound();
        }

        return ILMPVault(vault).rewarder();
    }
}
