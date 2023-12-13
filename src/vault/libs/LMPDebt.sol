// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";

library LMPDebt {
    using Math for uint256;
    using SafeERC20 for IERC20;

    error VaultShutdown();
    error WithdrawShareCalcInvalid(uint256 currentShares, uint256 cachedShares);
    error RebalanceDestinationsMatch(address destinationVault);
    error RebalanceFailed(string message);

    struct DestinationInfo {
        /// @notice Current underlying and reward value at the destination vault
        /// @dev Used for calculating totalDebt of the LMPVault
        uint256 currentDebt;
        /// @notice Last block timestamp this info was updated
        uint256 lastReport;
        /// @notice How many shares of the destination vault we owned at last report
        uint256 ownedShares;
        /// @notice Amount of baseAsset transferred out in service of deployments
        /// @dev Used for calculating 'in profit' or not during user withdrawals
        uint256 debtBasis;
    }

    struct RebalanceOutParams {
        /// Address that will received the withdrawn underlyer
        address receiver;
        /// The "out" destination vault
        address destinationOut;
        /// The amount of tokenOut that will be withdrawn
        uint256 amountOut;
        /// The underlyer for destinationOut
        address tokenOut;
        IERC20 _baseAsset;
        bool _shutdown;
    }

    /// @dev In memory struct only for managing vars in rebalances
    struct IdleDebtChange {
        uint256 debtDecrease;
        uint256 debtIncrease;
        uint256 idleDecrease;
        uint256 idleIncrease;
    }

    struct FlashRebalanceParams {
        uint256 totalIdle;
        uint256 totalDebt;
        IERC20 baseAsset;
        bool shutdown;
    }

    struct FlashResultInfo {
        uint256 tokenInBalanceBefore;
        uint256 tokenInBalanceAfter;
        bytes32 flashResult;
    }

    function flashRebalance(
        DestinationInfo storage destInfoOut,
        DestinationInfo storage destInfoIn,
        IERC3156FlashBorrower receiver,
        IStrategy.RebalanceParams memory params,
        IStrategy.SummaryStats memory destSummaryOut,
        ILMPStrategy lmpStrategy,
        FlashRebalanceParams memory flashParams,
        bytes calldata data
    ) external returns (uint256 idle, uint256 debt) {
        LMPDebt.IdleDebtChange memory idleDebtChange;

        // Handle decrease (shares going "Out", cashing in shares and sending underlying back to swapper)
        // If the tokenOut is _asset we assume they are taking idle
        // which is already in the contract
        idleDebtChange = _handleRebalanceOut(
            LMPDebt.RebalanceOutParams({
                receiver: address(receiver),
                destinationOut: params.destinationOut,
                amountOut: params.amountOut,
                tokenOut: params.tokenOut,
                _baseAsset: flashParams.baseAsset,
                _shutdown: flashParams.shutdown
            }),
            destInfoOut
        );

        // Handle increase (shares coming "In", getting underlying from the swapper and trading for new shares)
        if (params.amountIn > 0) {
            FlashResultInfo memory flashResultInfo;
            // get "before" counts
            flashResultInfo.tokenInBalanceBefore = IERC20(params.tokenIn).balanceOf(address(this));

            // Give control back to the solver so they can make use of the "out" assets
            // and get our "in" asset
            flashResultInfo.flashResult = receiver.onFlashLoan(msg.sender, params.tokenIn, params.amountIn, 0, data);

            // We assume the solver will send us the assets
            flashResultInfo.tokenInBalanceAfter = IERC20(params.tokenIn).balanceOf(address(this));

            // Make sure the call was successful and verify we have at least the assets we think
            // we were getting
            if (
                flashResultInfo.flashResult != keccak256("ERC3156FlashBorrower.onFlashLoan")
                    || flashResultInfo.tokenInBalanceAfter < flashResultInfo.tokenInBalanceBefore + params.amountIn
            ) {
                revert Errors.FlashLoanFailed(params.tokenIn, params.amountIn);
            }

            {
                // make sure we have a valid path
                (bool success, string memory message) = lmpStrategy.verifyRebalance(params, destSummaryOut);
                if (!success) {
                    revert RebalanceFailed(message);
                }
            }

            if (params.tokenIn != address(flashParams.baseAsset)) {
                (uint256 debtDecreaseIn, uint256 debtIncreaseIn) = _handleRebalanceIn(
                    destInfoIn,
                    IDestinationVault(params.destinationIn),
                    params.tokenIn,
                    flashResultInfo.tokenInBalanceAfter
                );
                idleDebtChange.debtDecrease += debtDecreaseIn;
                idleDebtChange.debtIncrease += debtIncreaseIn;
            } else {
                idleDebtChange.idleIncrease +=
                    flashResultInfo.tokenInBalanceAfter - flashResultInfo.tokenInBalanceBefore;
            }
        }

        {
            idle = flashParams.totalIdle;
            debt = flashParams.totalDebt;

            if (idleDebtChange.idleDecrease > 0 || idleDebtChange.idleIncrease > 0) {
                idle = idle + idleDebtChange.idleIncrease - idleDebtChange.idleDecrease;
            }

            if (idleDebtChange.debtDecrease > 0 || idleDebtChange.debtIncrease > 0) {
                debt = debt + idleDebtChange.debtIncrease - idleDebtChange.debtDecrease;
            }
        }
    }

    function _calcUserWithdrawSharesToBurn(
        DestinationInfo storage destInfo,
        IDestinationVault destVault,
        uint256 userShares,
        uint256 maxAssetsToPull,
        uint256 totalVaultShares
    ) external returns (uint256 sharesToBurn, uint256 totalDebtBurn) {
        // Figure out how many shares we can burn from the destination as well
        // as what our totalDebt deduction should be (totalDebt being a cached value).
        // If the destination vault is currently sitting at a profit, then the user can burn
        // all the shares this vault owns. If its at a loss, they can only burn an amount
        // proportional to their ownership of this vault. This is so a user doesn't lock in
        // a loss for the entire vault during their withdrawal

        uint256 currentDvShares = destVault.balanceOf(address(this));

        // slither-disable-next-line incorrect-equality
        if (currentDvShares == 0) {
            return (0, 0);
        }

        // Calculate the current value of our shares
        uint256 currentDvDebtValue = destVault.debtValue(currentDvShares);

        // Get the basis for the current deployment
        uint256 cachedDebtBasis = destInfo.debtBasis;

        // The amount of shares we had at the last debt reporting
        uint256 cachedDvShares = destInfo.ownedShares;

        // The value of our debt + earned rewards at last debt reporting
        uint256 cachedCurrentDebt = destInfo.currentDebt;

        // Our current share balance should only ever be lte the last snapshot
        // Any update to the deployment should update the snapshot and withdrawals
        // can only lower it
        if (currentDvShares > cachedDvShares) {
            revert WithdrawShareCalcInvalid(currentDvShares, cachedDvShares);
        }

        // Recalculated what the debtBasis is with the current number of shares
        uint256 updatedDebtBasis = cachedDebtBasis.mulDiv(currentDvShares, cachedDvShares, Math.Rounding.Up);

        // Neither of these numbers include rewards from the DV
        if (currentDvDebtValue < updatedDebtBasis) {
            // We are currently sitting at a loss. Limit the value we can pull from
            // the destination vault
            currentDvDebtValue = currentDvDebtValue.mulDiv(userShares, totalVaultShares, Math.Rounding.Down);
            currentDvShares = currentDvShares.mulDiv(userShares, totalVaultShares, Math.Rounding.Down);
        }

        // Shouldn't pull more than we want
        // Or, we're not in profit so we limit the pull
        if (currentDvDebtValue < maxAssetsToPull) {
            maxAssetsToPull = currentDvDebtValue;
        }

        // Calculate the portion of shares to burn based on the assets we need to pull
        // and the current total debt value. These are destination vault shares.
        sharesToBurn = currentDvShares.mulDiv(maxAssetsToPull, currentDvDebtValue, Math.Rounding.Up);

        // This is what will be deducted from totalDebt with the withdrawal. The totalDebt number
        // is calculated based on the cached values so we need to be sure to reduce it
        // proportional to the original cached debt value
        totalDebtBurn = cachedCurrentDebt.mulDiv(sharesToBurn, cachedDvShares, Math.Rounding.Up);
    }

    /// @notice Perform deposit and debt info update for the "in" destination during a rebalance
    /// @dev This "in" function performs less validations than its "out" version
    /// @param dvIn The "in" destination vault
    /// @param tokenIn The underlyer for dvIn
    /// @param depositAmount The amount of tokenIn that will be deposited
    /// @return debtDecrease The previous amount of debt dvIn accounted for in totalDebt
    /// @return debtIncrease The current amount of debt dvIn should account for in totalDebt
    function handleRebalanceIn(
        DestinationInfo storage destInfo,
        IDestinationVault dvIn,
        address tokenIn,
        uint256 depositAmount
    ) external returns (uint256 debtDecrease, uint256 debtIncrease) {
        (debtDecrease, debtIncrease) = _handleRebalanceIn(destInfo, dvIn, tokenIn, depositAmount);
    }

    /// @notice Perform deposit and debt info update for the "in" destination during a rebalance
    /// @dev This "in" function performs less validations than its "out" version
    /// @param dvIn The "in" destination vault
    /// @param tokenIn The underlyer for dvIn
    /// @param depositAmount The amount of tokenIn that will be deposited
    /// @return debtDecrease The previous amount of debt dvIn accounted for in totalDebt
    /// @return debtIncrease The current amount of debt dvIn should account for in totalDebt
    function _handleRebalanceIn(
        DestinationInfo storage destInfo,
        IDestinationVault dvIn,
        address tokenIn,
        uint256 depositAmount
    ) private returns (uint256 debtDecrease, uint256 debtIncrease) {
        LibAdapter._approve(IERC20(tokenIn), address(dvIn), depositAmount);

        // Snapshot our current shares so we know how much to back out
        uint256 originalShareBal = dvIn.balanceOf(address(this));

        // deposit to dv
        uint256 newShares = dvIn.depositUnderlying(depositAmount);

        // Update the debt info snapshot
        (debtDecrease, debtIncrease) =
            _recalculateDestInfo(destInfo, dvIn, originalShareBal, originalShareBal + newShares, true);
    }

    /**
     * @notice Perform withdraw and debt info update for the "out" destination during a rebalance
     * @dev This "out" function performs more validations and handles idle as opposed to "in" which does not
     *  debtDecrease The previous amount of debt destinationOut accounted for in totalDebt
     *  debtIncrease The current amount of debt destinationOut should account for in totalDebt
     *  idleDecrease Amount of baseAsset that was sent from the vault. > 0 only when tokenOut == baseAsset
     *  idleIncrease Amount of baseAsset that was claimed from Destination Vault
     * @param params Rebalance out params
     * @param destOutInfo The "out" destination vault info
     * @return assetChange debt and idle change data
     */
    function handleRebalanceOut(
        RebalanceOutParams memory params,
        DestinationInfo storage destOutInfo
    ) external returns (IdleDebtChange memory assetChange) {
        (assetChange) = _handleRebalanceOut(params, destOutInfo);
    }

    /**
     * @notice Perform withdraw and debt info update for the "out" destination during a rebalance
     * @dev This "out" function performs more validations and handles idle as opposed to "in" which does not
     *  debtDecrease The previous amount of debt destinationOut accounted for in totalDebt
     *  debtIncrease The current amount of debt destinationOut should account for in totalDebt
     *  idleDecrease Amount of baseAsset that was sent from the vault. > 0 only when tokenOut == baseAsset
     *  idleIncrease Amount of baseAsset that was claimed from Destination Vault
     * @param params Rebalance out params
     * @param destOutInfo The "out" destination vault info
     * @return assetChange debt and idle change data
     */
    function _handleRebalanceOut(
        RebalanceOutParams memory params,
        DestinationInfo storage destOutInfo
    ) private returns (IdleDebtChange memory assetChange) {
        // Handle decrease (shares going "Out", cashing in shares and sending underlying back to swapper)
        // If the tokenOut is _asset we assume they are taking idle
        // which is already in the contract
        if (params.amountOut > 0) {
            if (params.tokenOut != address(params._baseAsset)) {
                IDestinationVault dvOut = IDestinationVault(params.destinationOut);

                // Snapshot our current shares so we know how much to back out
                uint256 originalShareBal = dvOut.balanceOf(address(this));

                // Burning our shares will claim any pending baseAsset
                // rewards and send them to us. Make sure we capture them
                // so they can end up in idle
                uint256 beforeBaseAssetBal = params._baseAsset.balanceOf(address(this));

                // withdraw underlying from dv
                // slither-disable-next-line unused-return
                dvOut.withdrawUnderlying(params.amountOut, params.receiver);

                assetChange.idleIncrease = params._baseAsset.balanceOf(address(this)) - beforeBaseAssetBal;

                // Update the debt info snapshot
                (assetChange.debtDecrease, assetChange.debtIncrease) = _recalculateDestInfo(
                    destOutInfo, dvOut, originalShareBal, originalShareBal - params.amountOut, true
                );
            } else {
                // If we are shutdown then the only operations we should be performing are those that get
                // the base asset back to the vault. We shouldn't be sending out more
                if (params._shutdown) {
                    revert VaultShutdown();
                }
                // Working with idle baseAsset which should be in the vault already
                // Just send it out
                IERC20(params.tokenOut).safeTransfer(params.receiver, params.amountOut);
                assetChange.idleDecrease = params.amountOut;
            }
        }
    }

    function recalculateDestInfo(
        DestinationInfo storage destInfo,
        IDestinationVault destVault,
        uint256 originalShares,
        uint256 currentShares,
        bool resetDebtBasis
    ) external returns (uint256 totalDebtDecrease, uint256 totalDebtIncrease) {
        (totalDebtDecrease, totalDebtIncrease) =
            _recalculateDestInfo(destInfo, destVault, originalShares, currentShares, resetDebtBasis);
    }

    function _recalculateDestInfo(
        DestinationInfo storage destInfo,
        IDestinationVault destVault,
        uint256 originalShares,
        uint256 currentShares,
        bool resetDebtBasis
    ) private returns (uint256 totalDebtDecrease, uint256 totalDebtIncrease) {
        // Figure out what to back out of our totalDebt number.
        // We could have had withdraws since the last snapshot which means our
        // cached currentDebt number should be decreased based on the remaining shares
        // totalDebt is decreased using the same proportion of shares method during withdrawals
        // so this should represent whatever is remaining.

        // Figure out how much our debt is currently worth
        uint256 dvDebtValue = destVault.debtValue(currentShares);

        // Calculate what we're backing out based on the original shares
        uint256 currentDebt = (destInfo.currentDebt * originalShares) / Math.max(destInfo.ownedShares, 1);
        destInfo.currentDebt = dvDebtValue;
        destInfo.lastReport = block.timestamp;
        destInfo.ownedShares = currentShares;
        if (resetDebtBasis) {
            destInfo.debtBasis = dvDebtValue;
        }

        totalDebtDecrease = currentDebt;
        totalDebtIncrease = dvDebtValue;
    }
}
