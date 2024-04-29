// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ILMPVault, ILMPVaultRouterBase, IMainRewarder } from "src/interfaces/vault/ILMPVaultRouterBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { SelfPermit } from "src/utils/SelfPermit.sol";
import { PeripheryPayments } from "src/utils/PeripheryPayments.sol";
import { Multicall } from "src/utils/Multicall.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

import { LMPVault } from "src/vault/LMPVault.sol";

/// @title LMPVault Router Base Contract
abstract contract LMPVaultRouterBase is
    ILMPVaultRouterBase,
    SelfPermit,
    Multicall,
    PeripheryPayments,
    SystemComponent
{
    error UserNotAllowed();

    modifier onlyAllowedUsers(ILMPVault vault, address user) {
        if (LMPVault(address(vault))._checkUsers() && !LMPVault(address(vault)).allowedUsers(user)) {
            revert UserNotAllowed();
        }
        _;
    }

    //read weth from system registry and give it to periphery payments
    constructor(ISystemRegistry _systemRegistry)
        PeripheryPayments(_systemRegistry.weth())
        SystemComponent(_systemRegistry)
    { }

    //compose a multi call here
    /// @inheritdoc ILMPVaultRouterBase
    function mint(
        ILMPVault vault,
        address to,
        uint256 shares,
        uint256 maxAmountIn
    )
        public
        payable
        virtual
        override
        onlyAllowedUsers(vault, msg.sender)
        onlyAllowedUsers(vault, to)
        returns (uint256 amountIn)
    {
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
        if ((sharesOut = vault.deposit(amount, to)) < minSharesOut) {
            revert MinSharesError();
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function withdraw(
        ILMPVault vault,
        address to,
        uint256 amount,
        uint256 maxSharesOut
    )
        public
        payable
        virtual
        override
        onlyAllowedUsers(vault, msg.sender)
        onlyAllowedUsers(vault, to)
        returns (uint256 sharesOut)
    {
        sharesOut = vault.withdraw(amount, to, msg.sender);
        if (sharesOut > maxSharesOut) {
            revert MaxSharesError();
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function redeem(
        ILMPVault vault,
        address to,
        uint256 shares,
        uint256 minAmountOut
    )
        public
        payable
        virtual
        override
        onlyAllowedUsers(vault, msg.sender)
        onlyAllowedUsers(vault, to)
        returns (uint256 amountOut)
    {
        if ((amountOut = vault.redeem(shares, to, msg.sender)) < minAmountOut) {
            revert MinAmountError();
        }
    }

    /// @inheritdoc ILMPVaultRouterBase
    function stakeVaultToken(IERC20 vault, uint256 maxAmount) external returns (uint256) {
        _checkVault(address(vault));
        IMainRewarder lmpRewarder = ILMPVault(address(vault)).rewarder();

        uint256 userBalance = vault.balanceOf(address(this));
        if (userBalance < maxAmount) {
            maxAmount = userBalance;
        }

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
