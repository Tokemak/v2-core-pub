// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20, SafeERC20, Address } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ILMPVault, ILMPVaultRouterBase, IMainRewarder } from "src/interfaces/vault/ILMPVaultRouterBase.sol";
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
    function stakeVaultToken(IERC20 vault, uint256 maxAmount) external returns (uint256) {
        _checkVault(address(vault));
        IMainRewarder lmpRewarder = ILMPVault(address(vault)).rewarder();

        uint256 userBalance = vault.balanceOf(msg.sender);
        if (userBalance < maxAmount) {
            maxAmount = userBalance;
        }
        pullToken(vault, maxAmount, address(this));
        approve(vault, address(lmpRewarder), maxAmount);

        lmpRewarder.stake(msg.sender, maxAmount);

        return maxAmount;
    }

    /// @inheritdoc ILMPVaultRouterBase
    function withdrawVaultToken(
        ILMPVault vault,
        IMainRewarder rewarder,
        uint256 maxAmount,
        bool claim
    ) external returns (uint256) {
        _checkVault(address(vault));
        _checkRewarder(vault, address(rewarder));

        uint256 userRewardBalance = rewarder.balanceOf(msg.sender);
        if (maxAmount > userRewardBalance) {
            maxAmount = userRewardBalance;
        }

        rewarder.withdraw(msg.sender, maxAmount, claim);

        return maxAmount;
    }

    /// @inheritdoc ILMPVaultRouterBase
    function claimRewards(ILMPVault vault, IMainRewarder rewarder) external {
        _checkVault(address(vault));
        _checkRewarder(vault, address(rewarder));

        // Always claims any extra rewards that exist.
        rewarder.getReward(msg.sender, true);
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
    function _checkVault(address vault) internal view {
        if (!systemRegistry.lmpVaultRegistry().isVault(vault)) {
            revert Errors.ItemNotFound();
        }
    }

    function _checkRewarder(ILMPVault vault, address rewarder) internal view {
        if (rewarder != address(vault.rewarder()) && !vault.isPastRewarder(rewarder)) {
            revert Errors.ItemNotFound();
        }
    }
}
