// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

import { ILMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";

import { hevm } from "test/echidna/fuzz/utils/Hevm.sol";
import { BasePoolSetup } from "test/echidna/fuzz/vault/BaseSetup.sol";

import { TestERC20 } from "test/mocks/TestERC20.sol";
import { ERC2612 } from "test/utils/ERC2612.sol";

contract LMPVaultRouterUsage is BasePoolSetup {
    TestERC20 internal _vaultAsset;
    LMPVaultRouter internal lmpVaultRouter;

    ///@dev The user shares balance at the beginning of the last operation that shouldn't have changed
    uint256 internal _userSharesAtStart;

    ///@dev The user shares balance at the end of the last operation that shouldn't have changed
    uint256 internal _userSharesAtEnd;

    ///@dev modifier to help track User 1 shares on
    modifier updateUser1Balance() {
        _userSharesAtStart = _pool.balanceOf(_user1);
        _;
        _userSharesAtEnd = _pool.balanceOf(_user1);
    }

    constructor() BasePoolSetup() {
        _vaultAsset = new TestERC20("vaultAsset", "vaultAsset");
        _vaultAsset.setDecimals(18);
        initializeBaseSetup(address(_vaultAsset));

        _pool.initialize(address(_strategy), "SYMBOL", "NAME", abi.encode(""));
        _pool.setDisableNavDecreaseCheck(true);
        _pool.setCryticFnsEnabled(false);

        lmpVaultRouter = new LMPVaultRouter(_systemRegistry, address(_weth));

        _pool.toggleAllowedUser(address(this));
        _pool.toggleAllowedUser(_user1);
        _pool.toggleAllowedUser(_user2);
        _pool.toggleAllowedUser(_user3);
        _pool.toggleAllowedUser(address(lmpVaultRouter));
    }

    ///@dev Only mint for Users
    function mintAssetForUser(address user, uint256 assets, uint256 approveAmount, uint256 shares) public {
        if (user != _user1 || user != _user2 || user != _user3) {
            revert("invalid params");
        }
        _vaultAsset.mint(address(this), assets);
        _vaultAsset.approve(address(_pool), approveAmount);
        _pool.mint(uint256(shares), user);
    }

    ///@dev Shares can be only minted to User1
    function mint(
        ILMPVault vault,
        uint256 shares,
        uint256 maxAmountIn
    ) public updateUser1Balance returns (uint256 amountIn) {
        address to = _user1;
        return lmpVaultRouter.mint(vault, to, shares, maxAmountIn);
    }

    ///@dev Only User1 can deposit
    function deposit(
        ILMPVault vault,
        uint256 amount,
        uint256 minSharesOut
    ) public updateUser1Balance returns (uint256 sharesOut) {
        address to = _user1;
        return lmpVaultRouter.deposit(vault, to, amount, minSharesOut);
    }

    ///@dev Anyone can permit
    function permit(address user, uint256 amount, address receiver) public {
        uint256 signerKey = 1;

        // Setup for the Spender to spend the Users tokens
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = ERC2612.getPermitSignature(
            _pool.DOMAIN_SEPARATOR(), signerKey, user, address(lmpVaultRouter), amount, 0, deadline
        );

        hevm.prank(user);
        lmpVaultRouter.selfPermit(address(_pool), amount, deadline, v, r, s);
    }

    ///@dev Anyone but User1 can try withdraw
    function withdraw(
        ILMPVault vault,
        address to,
        uint256 amount,
        uint256 maxSharesOut,
        bool unwrapWETH
    ) public updateUser1Balance returns (uint256 sharesOut) {
        if (to == _user1 || address(vault) == to) {
            revert("invalid params");
        }
        return lmpVaultRouter.withdraw(vault, to, amount, maxSharesOut, unwrapWETH);
    }

    ///@dev Anyone but User1 can try redeem
    function redeem(
        ILMPVault vault,
        address to,
        uint256 shares,
        uint256 minAmountOut,
        bool unwrapWETH
    ) public updateUser1Balance returns (uint256 amountOut) {
        if (to == _user1 || address(vault) == to) {
            revert("invalid params");
        }
        return lmpVaultRouter.redeem(vault, to, shares, minAmountOut, unwrapWETH);
    }

    ///@dev Anyone can stake VaultToken
    function stakeVaultToken(IERC20 vault, uint256 maxAmount) public returns (uint256 staked) {
        return lmpVaultRouter.stakeVaultToken(vault, maxAmount);
    }

    ///@dev Anyone can try to withdraw VaultToken
    function withdrawVaultToken(
        ILMPVault vault,
        IMainRewarder rewarder,
        uint256 maxAmount,
        bool claim
    ) public returns (uint256 withdrawn) {
        if (address(vault) == address(rewarder)) {
            revert("invalid params");
        }
        return lmpVaultRouter.withdrawVaultToken(vault, rewarder, maxAmount, claim);
    }

    ///@dev Anyone can try to claim rewards
    function claimRewards(ILMPVault vault, IMainRewarder rewarder) public updateUser1Balance {
        if (address(vault) == address(rewarder)) {
            revert("invalid params");
        }
        return lmpVaultRouter.claimRewards(vault, rewarder);
    }

    ///@dev Only User1 can swap to deposit
    function swapAndDepositToVault(
        address swapper,
        SwapParams memory swapParams,
        ILMPVault vault,
        uint256 minSharesOut
    ) public updateUser1Balance returns (uint256 sharesOut) {
        address to = _user1;
        return lmpVaultRouter.swapAndDepositToVault(swapper, swapParams, vault, to, minSharesOut);
    }

    ///@dev Only User1 can deposit
    function depositMax(ILMPVault vault, uint256 minSharesOut) public updateUser1Balance returns (uint256 sharesOut) {
        //Only User1 can deposit
        address to = _user1;
        return lmpVaultRouter.depositMax(vault, to, minSharesOut);
    }

    ///@dev Anyone but User1 can try withdraw to deposit
    function withdrawToDeposit(
        ILMPVault fromVault,
        ILMPVault toVault,
        address to,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) public updateUser1Balance returns (uint256 sharesOut) {
        if (
            to == _user1 || address(fromVault) == address(toVault) || address(fromVault) == to || address(toVault) == to
        ) {
            revert("invalid params");
        }
        return lmpVaultRouter.withdrawToDeposit(fromVault, toVault, to, amount, maxSharesIn, minSharesOut);
    }

    ///@dev Anyone but User1 can try redeem to deposit
    function redeemToDeposit(
        ILMPVault fromVault,
        ILMPVault toVault,
        address to,
        uint256 shares,
        uint256 minSharesOut
    ) public updateUser1Balance returns (uint256 sharesOut) {
        if (
            to == _user1 || address(fromVault) == address(toVault) || address(fromVault) == to || address(toVault) == to
        ) {
            revert("invalid params");
        }
        return lmpVaultRouter.redeemToDeposit(fromVault, toVault, to, shares, minSharesOut);
    }

    ///@dev Anyone but User1 can redeem max
    function redeemMax(
        ILMPVault vault,
        address to,
        uint256 minAmountOut
    ) public updateUser1Balance returns (uint256 amountOut) {
        if (to == _user1 || address(vault) == to) {
            revert("invalid params");
        }
        return lmpVaultRouter.redeemMax(vault, to, minAmountOut);
    }
}

contract LMPVaultRouterTest is LMPVaultRouterUsage {
    constructor() LMPVaultRouterUsage() { }

    // Check that User 1 shares didn't change
    function echidna_no_other_user_can_redeem_through_router_using_permit() public view returns (bool) {
        return _userSharesAtEnd == _userSharesAtStart;
    }
}
