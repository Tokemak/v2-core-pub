// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { Errors } from "src/utils/Errors.sol";

library BalancerBeethovenAdapter {
    event DeployLiquidity(
        uint256[] amountsDeposited,
        address[] tokens,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        bytes32 poolId
    );

    event WithdrawLiquidity(
        uint256[] amountsWithdrawn,
        address[] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        bytes32 poolId
    );

    error TokenPoolAssetMismatch();
    error ArraysLengthMismatch();
    error BalanceMustIncrease();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();

    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
        ADD_TOKEN
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT,
        REMOVE_TOKEN
    }

    enum ExitKindComposable {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT,
        EXACT_BPT_IN_FOR_ALL_TOKENS_OUT
    }
    /**
     * @param pool address of Balancer Pool
     * @param bptAmount uint256 pool token amount expected back
     * @param tokens IERC20[] of tokens to be withdrawn from pool
     * @param amountsOut uint256[] min amount of tokens expected on withdrawal
     * @param userData bytes data, used for info about kind of pool exit
     */

    struct WithdrawParams {
        address pool;
        uint256 bptAmount;
        address[] tokens;
        uint256[] amountsOut;
        bytes userData;
    }

    /**
     * @notice Deploy liquidity to Balancer or Beethoven pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to deploy liquidity to
     * @param tokens Addresses of tokens to deploy. Should match pool tokens
     * @param exactTokenAmounts Array of exact amounts of tokens to be deployed
     * @param minLpMintAmount Min amount of LP tokens to mint on deposit
     */
    function addLiquidity(
        IVault vault,
        address pool,
        address[] calldata tokens,
        uint256[] calldata exactTokenAmounts,
        uint256 minLpMintAmount
    ) public {
        uint256 nTokens = tokens.length;
        if (nTokens == 0 || nTokens != exactTokenAmounts.length) {
            revert ArraysLengthMismatch();
        }
        Errors.verifyNotZero(address(vault), "vault");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(minLpMintAmount, "minLpMintAmount");

        uint256[] memory assetBalancesBefore = new uint256[](nTokens);
        bytes32 poolId = IBalancerPool(pool).getPoolId();

        // verify that we're passing correct pool tokens
        _ensureTokenOrderAndApprovals(vault, exactTokenAmounts, tokens, poolId, assetBalancesBefore);

        // record BPT balances before deposit 0 - balance before; 1 - balance after
        uint256[] memory bptBalances = new uint256[](2);
        bptBalances[0] = IBalancerPool(pool).balanceOf(address(this));

        vault.joinPool(
            poolId,
            address(this), // sender
            address(this), // recipient of BPT token
            _getJoinPoolRequest(pool, tokens, exactTokenAmounts, minLpMintAmount)
        );

        // make sure we received bpt
        bptBalances[1] = IBalancerPool(pool).balanceOf(address(this));
        if (bptBalances[1] < bptBalances[0] + minLpMintAmount) {
            revert BalanceMustIncrease();
        }
        // make sure we spent exactly how much we wanted
        for (uint256 i = 0; i < nTokens; ++i) {
            //slither-disable-next-line calls-loop
            uint256 currentBalance = IERC20(tokens[i]).balanceOf(address(this));

            if (currentBalance != assetBalancesBefore[i] - exactTokenAmounts[i]) {
                // For composable pools it might be a case that we deposit 0 LP tokens and our LP balance increases
                if (address(tokens[i]) != address(pool)) {
                    revert InvalidBalanceChange();
                }
            }
        }

        _emitDeploy(exactTokenAmounts, tokens, bptBalances, pool, poolId);
    }

    /**
     * @notice Withdraw liquidity from Balancer or Beethoven pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to withdrawn liquidity from
     * @param tokens Addresses of tokens to withdraw. Should match pool tokens
     * @param exactAmountsOut Array of exact amounts of tokens to be withdrawn from pool
     * @param maxLpBurnAmount Max amount of LP tokens to burn in the withdrawal
     */
    function removeLiquidity(
        IVault vault,
        address pool,
        address[] calldata tokens,
        uint256[] calldata exactAmountsOut,
        uint256 maxLpBurnAmount
    ) public returns (uint256[] memory actualAmounts) {
        bytes memory userData;
        if (BalancerUtilities.isComposablePool(pool)) {
            userData = abi.encode(ExitKindComposable.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, maxLpBurnAmount);
        } else {
            userData = abi.encode(ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, exactAmountsOut, maxLpBurnAmount);
            // Verify if at least one non-zero amount is present
            bool hasNonZeroAmount = false;
            uint256 nTokens = exactAmountsOut.length;
            for (uint256 i = 0; i < nTokens; ++i) {
                if (exactAmountsOut[i] != 0) {
                    hasNonZeroAmount = true;
                    break;
                }
            }
            if (!hasNonZeroAmount) {
                revert NoNonZeroAmountProvided();
            }
        }

        actualAmounts = _withdraw(
            vault,
            WithdrawParams({
                pool: pool,
                bptAmount: maxLpBurnAmount,
                tokens: tokens,
                amountsOut: exactAmountsOut,
                userData: userData
            })
        );
    }

    /**
     * @notice Withdraw liquidity from Balancer V2 pool (specifying exact LP tokens to burn)
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to liquidity withdrawn from
     * @param exactLpBurnAmount Amount of LP tokens to burn in the withdrawal
     * @param minAmountsOut Array of minimum amounts of tokens to be withdrawn from pool
     */
    function removeLiquidityImbalance(
        IVault vault,
        address pool,
        uint256 exactLpBurnAmount,
        address[] memory tokens,
        uint256[] memory minAmountsOut
    ) public returns (uint256[] memory withdrawnAmounts) {
        bytes memory userData = abi.encode(ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, exactLpBurnAmount);

        withdrawnAmounts = _withdraw(
            vault,
            WithdrawParams({
                pool: pool,
                bptAmount: exactLpBurnAmount,
                tokens: tokens,
                amountsOut: minAmountsOut,
                userData: userData
            })
        );
    }

    /**
     * @notice Withdraw liquidity from Balancer V2 pool (specifying exact LP tokens to burn)
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to liquidity withdrawn from
     * @param exactLpBurnAmount Amount of LP tokens to burn in the withdrawal
     * @param minAmountsOut Array of minimum amounts of tokens to be withdrawn from pool
     * @param exitTokenIndex Index of token to withdraw in
     */
    function removeLiquidityComposableImbalance(
        IVault vault,
        address pool,
        uint256 exactLpBurnAmount,
        address[] memory tokens,
        uint256[] calldata minAmountsOut,
        uint256 exitTokenIndex
    ) external returns (uint256[] memory withdrawnAmounts) {
        bytes memory userData =
            abi.encode(ExitKindComposable.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, exactLpBurnAmount, exitTokenIndex);

        withdrawnAmounts = _withdraw(
            vault,
            WithdrawParams({
                pool: pool,
                bptAmount: exactLpBurnAmount,
                tokens: tokens,
                amountsOut: minAmountsOut,
                userData: userData
            })
        );
    }

    /**
     * @dev This is a helper function to avoid stack-too-deep-errors
     */
    function _emitDeploy(
        uint256[] calldata exactTokenAmounts,
        address[] calldata tokens,
        uint256[] memory bptBalances,
        address pool,
        bytes32 poolId
    ) private {
        emit DeployLiquidity(
            exactTokenAmounts,
            tokens,
            [bptBalances[1] - bptBalances[0], bptBalances[1], IERC20(pool).totalSupply()],
            pool,
            poolId
        );
    }

    /// @dev Helper method to avoid stack-too-deep-errors
    function _withdraw(IVault vault, WithdrawParams memory params) private returns (uint256[] memory amountsOut) {
        //slither-disable-start reentrancy-events

        address pool = params.pool;
        IBalancerPool poolInterface = IBalancerPool(pool);

        Errors.verifyNotZero(address(vault), "vault");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(params.bptAmount, "params.bptAmount");

        amountsOut = params.amountsOut;
        address[] memory tokens = params.tokens;

        uint256 nTokens = tokens.length;
        // slither-disable-next-line incorrect-equality
        if (nTokens == 0 || nTokens != amountsOut.length) {
            revert ArraysLengthMismatch();
        }

        bytes32 poolId = poolInterface.getPoolId();
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory poolTokens,,) = vault.getPoolTokens(poolId);

        if (poolTokens.length != nTokens) {
            revert ArraysLengthMismatch();
        }

        _verifyPoolTokensMatch(tokens, poolTokens);

        // Record balance before withdraw
        uint256 bptBalanceBefore = poolInterface.balanceOf(address(this));

        uint256[] memory assetBalancesBefore = new uint256[](nTokens);
        for (uint256 i = 0; i < nTokens; ++i) {
            assetBalancesBefore[i] = poolTokens[i].balanceOf(address(this));
        }

        // As we're exiting the pool we need to make an ExitPoolRequest instead
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: BalancerUtilities._convertERC20sToAddresses(poolTokens),
            minAmountsOut: amountsOut,
            userData: params.userData,
            toInternalBalance: false
        });
        vault.exitPool(
            poolId,
            address(this), // sender,
            payable(address(this)), // recipient,
            request
        );

        // Make sure we burned BPT, and assets were received
        uint256 bptBalanceAfter = poolInterface.balanceOf(address(this));
        if (bptBalanceAfter >= bptBalanceBefore) {
            revert InvalidBalanceChange();
        }

        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 assetBalanceBefore = assetBalancesBefore[i];

            IERC20 currentToken = poolTokens[i];
            if (address(currentToken) != pool) {
                uint256 currentBalance = currentToken.balanceOf(address(this));

                if (currentBalance < assetBalanceBefore + amountsOut[i]) {
                    revert BalanceMustIncrease();
                }
                // Get actual amount returned for event, reuse amountsOut array
                amountsOut[i] = currentBalance - assetBalanceBefore;
            }
        }
        emit WithdrawLiquidity(
            amountsOut,
            tokens,
            [bptBalanceBefore - bptBalanceAfter, bptBalanceAfter, poolInterface.totalSupply()],
            pool,
            poolId
        );
        //slither-disable-end reentrancy-events
    }

    // run through tokens and make sure it matches the pool's assets
    function _verifyPoolTokensMatch(address[] memory tokens, IERC20[] memory poolTokens) private pure {
        uint256 nTokens = tokens.length;
        for (uint256 i = 0; i < nTokens; ++i) {
            IERC20 currentToken = IERC20(tokens[i]);
            if (currentToken != poolTokens[i]) {
                revert TokenPoolAssetMismatch();
            }
        }
    }

    /**
     * @notice Validate that given tokens are relying to the given pool and approve spend
     * @dev Separate function to avoid stack-too-deep errors
     * and combine gas-costly loop operations into single loop
     * @param amounts Amounts of corresponding tokens to approve
     * @param poolId Balancer or Beethoven Pool ID
     * @param assetBalancesBefore Array to record initial token balances
     */
    function _ensureTokenOrderAndApprovals(
        IVault vault,
        uint256[] calldata amounts,
        address[] memory tokens,
        bytes32 poolId,
        uint256[] memory assetBalancesBefore
    ) private {
        // (two part verification: total number checked here, and individual match check below)

        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory poolAssets,,) = vault.getPoolTokens(poolId);

        uint256 nTokens = amounts.length;

        if (poolAssets.length != nTokens) {
            revert ArraysLengthMismatch();
        }

        // run through tokens and make sure we have approvals
        // for at least one non-zero amount (and correct token order)
        bool hasNonZeroAmount = false;
        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 currentAmount = amounts[i];
            IERC20 currentToken = IERC20(tokens[i]);

            // make sure asset is supported (and matches the pool's assets)
            if (currentToken != poolAssets[i]) {
                revert TokenPoolAssetMismatch();
            }
            // record previous balance for this asset
            assetBalancesBefore[i] = currentToken.balanceOf(address(this));

            // grant spending approval to balancer's Vault
            if (currentAmount != 0) {
                hasNonZeroAmount = true;
                LibAdapter._approve(currentToken, address(vault), currentAmount);
            }
        }
        if (!hasNonZeroAmount) {
            revert NoNonZeroAmountProvided();
        }
    }

    /**
     * @notice Generate request for Balancer's Vault to join the pool
     * @dev Separate function to avoid stack-too-deep errors
     * @param tokens Tokens to be deposited into pool
     * @param amounts Amounts of corresponding tokens to deposit
     * @param poolAmountOut Expected amount of LP tokens to be minted on deposit
     */
    function _getJoinPoolRequest(
        address pool,
        address[] memory tokens,
        uint256[] calldata amounts,
        uint256 poolAmountOut
    ) private view returns (IVault.JoinPoolRequest memory joinRequest) {
        uint256[] memory amountsUser;

        if (BalancerUtilities.isComposablePool(pool)) {
            uint256 nTokens = tokens.length;
            uint256 uix = 0;
            uint256 bptIndex = IBalancerComposableStablePool(pool).getBptIndex();
            amountsUser = new uint256[](nTokens - 1);
            for (uint256 i = 0; i < nTokens; i++) {
                if (i != bptIndex) {
                    amountsUser[uix] = amounts[i];
                    uix++;
                }
            }
        } else {
            amountsUser = amounts;
        }

        joinRequest = IVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amounts, // maxAmountsIn,
            userData: abi.encode(
                IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsUser, //maxAmountsIn,
                poolAmountOut
                ),
            fromInternalBalance: false
        });
    }
}
