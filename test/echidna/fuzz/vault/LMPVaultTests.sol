// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { WETH9 } from "test/echidna/fuzz/mocks/WETH9.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MockRootOracle } from "test/echidna/fuzz/mocks/MockRootOracle.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { AutoPoolFees } from "src/vault/libs/AutoPoolFees.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Numbers } from "test/echidna/fuzz/utils/Numbers.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { hevm } from "test/echidna/fuzz/utils/Hevm.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import {
    BasePoolSetup,
    TestingStrategy,
    TestingAccessController,
    TestingPool,
    TestDestinationVault,
    TestSolver
} from "test/echidna/fuzz/vault/BaseSetup.sol";
import { WETH9 } from "test/echidna/fuzz/mocks/WETH9.sol";

import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";

contract LMPVaultUsage is BasePoolSetup, Numbers {
    TestERC20 internal _vaultAsset;

    /// =====================================================
    /// State Tracking
    /// =====================================================

    // uint256 internal _user1TotalAssetsDeposited;
    // uint256 internal _user2TotalAssetsDeposited;
    // uint256 internal _user3TotalAssetsDeposited;

    // uint256 internal _user1TotalAssetsWithdrawn;
    // uint256 internal _user2TotalAssetsWithdrawn;
    // uint256 internal _user3TotalAssetsWithdrawn;

    /// @dev The nav/share at the beginning of the last operation that shouldn't have changed nav/share
    uint256 internal _navPerShareLastNonOpStart;

    /// @dev The nav/share at the end of the last operation that shouldn't have changed nav/share
    uint256 internal _navPerShareLastNonOpEnd;

    /// =====================================================
    /// Modifiers
    /// =====================================================

    modifier opNoNavPerShareChange(ILMPVault.TotalAssetPurpose purpose) {
        uint256 ts = _pool.totalSupply();
        uint256 start = 0;
        if (ts > 0) {
            start = (_pool.totalAssets(purpose) * AutoPoolFees.FEE_DIVISOR) / ts;
        }
        _;
        if (ts > 0) {
            ts = _pool.totalSupply();
            _navPerShareLastNonOpStart = start;
            _navPerShareLastNonOpEnd = (_pool.totalAssets(purpose) * AutoPoolFees.FEE_DIVISOR) / ts;
        }
    }

    /// =====================================================
    /// Constructor
    /// =====================================================

    constructor() BasePoolSetup() {
        // If you are running directly

        _vaultAsset = new TestERC20("vaultAsset", "vaultAsset");
        _vaultAsset.setDecimals(18);
        initializeBaseSetup(address(_vaultAsset));

        _pool.initialize(address(_strategy), "SYMBOL", "NAME", abi.encode(""));
        _pool.setDisableNavDecreaseCheck(true);
        _pool.setCryticFnsEnabled(false);
    }

    /// =====================================================
    /// Nav/Share Changing Ops
    /// =====================================================

    function debtReport(uint256 numToProcess) public {
        _pool.updateDebtReporting(numToProcess > 3 ? 3 : numToProcess);
    }

    function rebalance(uint8 destinationFrom, uint8 destinationTo, uint8 pctOut, int16 inTweak) public {
        uint256 from = scaleTo(destinationFrom, 3);
        uint256 to = scaleTo(destinationTo, 3);

        if (from == to) {
            revert("destinations match");
        }

        address destinationOut = from == 3 ? address(_pool) : _destinations[from];
        address fromUnderlying = from == 3 ? address(_vaultAsset) : IDestinationVault(_destinations[from]).underlying();
        address destinationIn = to == 3 ? address(_pool) : _destinations[to];
        address toUnderlying = to == 3 ? address(_vaultAsset) : IDestinationVault(_destinations[to]).underlying();

        uint256 amountOut = pctOf(
            from == 3
                ? _vaultAsset.balanceOf(address(_pool))
                : IDestinationVault(_destinations[from]).balanceOf(address(_pool)),
            pctOut
        );

        if (amountOut == 0) {
            revert("amountOut==0");
        }

        TestSolver.Details memory details =
            TestSolver.Details({ tokenSent: fromUnderlying, amountSent: amountOut, amountTweak: inTweak });

        // Can't expect too much positive slippage
        if (inTweak > int16(3000)) {
            inTweak = int16(3000);
        }

        uint256 amountIn = tweak16(_convertTokenAmountsByPrice(fromUnderlying, amountOut, toUnderlying), inTweak);

        IStrategy.RebalanceParams memory params = IStrategy.RebalanceParams({
            destinationIn: destinationIn,
            tokenIn: toUnderlying,
            amountIn: amountIn,
            destinationOut: destinationOut,
            tokenOut: fromUnderlying,
            amountOut: amountOut
        });

        uint256 valueComingIn = _rootPriceOracle.getPriceInEth(toUnderlying) * amountIn;
        uint256 valueGoingOut = _rootPriceOracle.getPriceInEth(fromUnderlying) * amountOut;

        // We'd only expect a few % loss in value in rebalance and it still be valid
        _strategy.setNextRebalanceSuccess((valueComingIn * 104) / 100 >= valueGoingOut);

        _pool.flashRebalance(_solver, params, abi.encode(details));
    }

    /// =====================================================
    /// Fees
    /// =====================================================

    function setStreamingFee(uint256 fee) public {
        _pool.setStreamingFeeBps(fee);
    }

    function setPeriodicFee(uint256 fee) public {
        _pool.setPeriodicFeeBps(fee);
    }

    function setStreamingFeeSink(address sink) public {
        if (
            sink == address(_pool) || sink == address(_destVault1) || sink == address(_destVault2)
                || sink == address(_destVault3) || sink == _user1 || sink == _user2 || sink == _user3
        ) {
            revert("invalid address");
        }

        _pool.setFeeSink(sink);
    }

    function setPeriodicFeeSink(address sink) public {
        if (
            sink == address(_pool) || sink == address(_destVault1) || sink == address(_destVault2)
                || sink == address(_destVault3) || sink == _user1 || sink == _user2 || sink == _user3
        ) {
            revert("invalid address");
        }

        _pool.setPeriodicFeeSink(sink);
    }

    /// =====================================================
    /// Rewards
    /// =====================================================

    function queueDestinationRewards(uint8 destVaultScale, uint256 amount) public {
        IBaseRewarder rewarder = IBaseRewarder(_destVaultFromScale(destVaultScale).rewarder());
        _vaultAsset.mint(address(this), amount);
        _vaultAsset.approve(address(rewarder), amount);
        rewarder.queueNewRewards(amount);
    }

    /// =====================================================
    /// Price and Slippage Updates
    /// =====================================================

    function tweakDestVaultUnderlyerPrice(uint8 destVaultScale, int8 tweak) public {
        _rootPriceOracle.tweakPrice(_destVaultFromScale(destVaultScale).underlying(), tweak);
    }

    function setDestVaultUnderlyerCeilingTweak(uint8 destVaultScale, uint8 tweak) public {
        _rootPriceOracle.setCeilingTweak(_destVaultFromScale(destVaultScale).underlying(), tweak);
    }

    function setDestVaultUnderlyerFloorTweak(uint8 destVaultScale, uint8 tweak) public {
        _rootPriceOracle.setFloorTweak(_destVaultFromScale(destVaultScale).underlying(), tweak);
    }

    function setDestVaultUnderlyerSafeTweak(uint8 destVaultScale, int8 tweak) public {
        _rootPriceOracle.setSafeTweak(_destVaultFromScale(destVaultScale).underlying(), tweak);
    }

    function setDestVaultUnderlyerSpotTweak(uint8 destVaultScale, int8 tweak) public {
        _rootPriceOracle.setSpotTweak(_destVaultFromScale(destVaultScale).underlying(), tweak);
    }

    function setSlippageOnNextDestVaultBurn(uint8 destVaultScale, int16 slippage) public {
        _destVaultFromScale(destVaultScale).setNextBurnSlippage(slippage);
    }

    /// =====================================================
    /// User Interactions
    /// =====================================================

    function userDeposit(
        uint8 userScale,
        uint96 assets,
        bool asUser
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Deposit) {
        _userDeposit(_userFromScale(userScale), assets, asUser);
    }

    function userDepositRoundingLoop(
        uint8 userScale,
        uint96 assets,
        uint8 loops,
        bool asUser
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Deposit) {
        address user = _userFromScale(userScale);
        _userDeposit(user, assets, asUser);
        _pool.increaseIdle(assets * 2);

        for (uint256 i = 0; i < loops; ++i) {
            uint256 totalAssets = _pool.totalAssets();
            _userDeposit(user, uint96(2 * totalAssets - 1), asUser);
            _userWithdraw(user, 1, address(0));
        }
    }

    function userMint(
        uint8 userScale,
        uint96 shares,
        bool asUser
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Deposit) {
        _userMint(_userFromScale(userScale), shares, asUser);
    }

    function userRedeem(
        uint8 userScale,
        uint96 shares
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Withdraw) {
        _userRedeem(_userFromScale(userScale), shares, address(0));
    }

    function userRedeemAllowance(
        uint8 userScale,
        uint96 shares,
        address allowedUser
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Withdraw) {
        _userRedeem(_userFromScale(userScale), shares, allowedUser);
    }

    function userWithdraw(
        uint8 userScale,
        uint96 assets
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Withdraw) {
        _userWithdraw(_userFromScale(userScale), assets, address(0));
    }

    function userWithdrawAllowance(
        uint8 userScale,
        uint96 assets,
        address allowedUser
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Withdraw) {
        _userWithdraw(_userFromScale(userScale), assets, allowedUser);
    }

    function userDonate(
        uint8 userScale,
        uint96 assets
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Global) {
        _userDonate(assets, _userFromScale(userScale));
    }

    function randomDonate(
        uint96 assets,
        address user
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Global) {
        if (_isValidImpersonatedUserAddress(user)) {
            _userDonate(assets, user);
        }
    }

    function userTransfer(
        uint8 userScale,
        uint96 shares,
        address destination
    ) public opNoNavPerShareChange(ILMPVault.TotalAssetPurpose.Global) {
        _userTransfer(shares, _userFromScale(userScale), destination);
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    function _destVaultFromScale(uint8 userScale) private view returns (TestDestinationVault) {
        uint256 u = scaleTo(userScale, 2);
        address d = _destinations[u];
        return TestDestinationVault(d);
    }

    function _userFromScale(uint8 userScale) private view returns (address) {
        uint256 u = scaleTo(userScale, 2);
        address user = _users[u];
        return user;
    }

    function _userTransfer(uint96 shares, address user, address destination) internal {
        if (destination == _user1 || destination == _user2 || destination == _user3) {
            return;
        }

        uint256 bal = _pool.balanceOf(user);
        if (shares > bal) {
            return;
        }

        hevm.prank(user);
        _pool.transfer(destination, shares);
    }

    function _userDonate(uint96 assets, address user) internal {
        _vaultAsset.mint(user, assets);

        hevm.prank(user);
        _vaultAsset.transfer(address(_pool), assets);
    }

    function _userWithdraw(address user, uint96 assets, address allowedUser) private returns (uint256 actualAssets) {
        uint256 shares = _pool.convertToShares(
            assets, _pool.totalAssets(ILMPVault.TotalAssetPurpose.Withdraw), _pool.totalSupply(), Math.Rounding.Down
        );
        uint256 bal = _pool.balanceOf(user);
        if (shares <= bal) {
            if (allowedUser == address(0)) {
                hevm.prank(user);
                actualAssets = _pool.withdraw(shares, user, user);
            } else {
                if (_isValidImpersonatedUserAddress(allowedUser)) {
                    hevm.prank(user);
                    _pool.approve(allowedUser, shares);

                    hevm.prank(allowedUser);
                    actualAssets = _pool.withdraw(shares, user, user);
                }
            }
        }
    }

    function _userRedeem(address user, uint96 shares, address allowedUser) private returns (uint256 assets) {
        uint256 bal = _pool.balanceOf(user);
        if (shares <= bal) {
            if (allowedUser == address(0)) {
                hevm.prank(user);
                assets = _pool.redeem(shares, user, user);
            } else {
                if (_isValidImpersonatedUserAddress(allowedUser)) {
                    hevm.prank(user);
                    _pool.approve(allowedUser, shares);

                    hevm.prank(allowedUser);
                    assets = _pool.redeem(shares, user, user);
                }
            }
        }
    }

    function _userMint(address user, uint96 shares, bool asUser) private returns (uint256 actualAssets) {
        uint256 assets = _pool.convertToAssets(
            shares, _pool.totalAssets(ILMPVault.TotalAssetPurpose.Deposit), _pool.totalSupply(), Math.Rounding.Up
        );
        if (asUser) {
            _vaultAsset.mint(user, assets * 2);

            hevm.prank(user);
            _vaultAsset.approve(address(_pool), assets * 2);

            hevm.prank(user);
            actualAssets = _pool.mint(uint256(shares), user);

            uint256 bal = _vaultAsset.balanceOf(user);
            if (bal > 0) {
                _vaultAsset.burn(user, bal);
            }
        } else {
            _vaultAsset.mint(address(this), assets * 2);
            _vaultAsset.approve(address(_pool), assets * 2);
            actualAssets = _pool.mint(uint256(shares), user);
            uint256 bal = _vaultAsset.balanceOf(user);
            if (bal > 0) {
                _vaultAsset.burn(user, bal);
            }
        }
    }

    function _userDeposit(address user, uint96 assets, bool asUser) private {
        if (asUser) {
            _vaultAsset.mint(user, uint256(assets));
            hevm.prank(user);
            _vaultAsset.approve(address(_pool), uint256(assets));
            hevm.prank(user);
            _pool.deposit(uint256(assets), user);
        } else {
            _vaultAsset.mint(address(this), uint256(assets));
            _vaultAsset.approve(address(_pool), uint256(assets));
            _pool.deposit(uint256(assets), user);
        }
    }

    function _isValidImpersonatedUserAddress(address user) private view returns (bool) {
        if (
            user == address(_pool) || user == address(_vaultAsset) || user == address(_toke) || user == address(_weth)
                || user == address(_destVault1) || user == address(_destVault2) || user == address(_destVault3)
        ) {
            return false;
        }
        return true;
    }

    function _convertTokenAmountsByPrice(
        address token,
        uint256 amount,
        address toToken
    ) internal view returns (uint256) {
        uint256 price = _rootPriceOracle.getPriceInEth(token);
        uint256 toPrice = _rootPriceOracle.getPriceInEth(toToken);

        if (toPrice == 0) {
            return 0;
        }
        return amount * price / toPrice;
    }
}

contract LMPVaultTest is LMPVaultUsage {
    constructor() LMPVaultUsage() { }

    function echidna_nav_per_share_cant_decrease_on_user_op() public view returns (bool) {
        return _navPerShareLastNonOpStart <= _navPerShareLastNonOpEnd;
    }

    function echidna_no_assets_left_in_vault() public view returns (bool) {
        uint256 ts = _pool.totalSupply();
        uint256 ta = _pool.totalAssets();
        if (ts == 0) {
            return ta == 0;
        }
        return true;
    }
}
