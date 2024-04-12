// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { IRouter } from "src/interfaces/external/maverick/IRouter.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

//slither-disable-start similar-names
library MaverickAdapter {
    event DeployLiquidity(
        uint256[2] amountsDeposited,
        address[2] tokens,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        uint256 receivingTokenId,
        uint256[] deployedBinIds
    );

    event WithdrawLiquidity(
        uint256[2] amountsWithdrawn,
        address[2] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        uint256 receivingTokenId,
        uint256[] deployedBinIds
    );

    error MustBeMoreThanZero();
    error ArraysLengthMismatch();
    error MinLpAmountNotReached();
    error LpTokenAmountMismatch();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();

    struct MaverickDeploymentExtraParams {
        address poolAddress;
        uint256 tokenId;
        uint256 deadline;
        IPool.AddLiquidityParams[] maverickParams;
    }

    struct MaverickWithdrawalExtraParams {
        address poolAddress;
        uint256 tokenId;
        uint256 deadline;
        IPool.RemoveLiquidityParams[] maverickParams;
    }

    /**
     * @notice Deploys liquidity to Maverick and receives a Position NFT from Maverick
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract. Caller should implement onERC721Received
     * function to receive Maverick Position NFT on deposit
     * @param router Maverick Router contract
     * @param amounts quantity of tokens to deposit
     * @param minLpMintAmount min amount of LP tokens to mint on deposit
     * @param extraParams encoded `MaverickDeploymentExtraParams`
     */
    function addLiquidity(
        IRouter router,
        uint256[] calldata amounts,
        uint256 minLpMintAmount,
        bytes calldata extraParams
    ) external {
        if (minLpMintAmount == 0) revert MustBeMoreThanZero();
        if (amounts.length != 2) revert ArraysLengthMismatch();
        if (amounts[0] == 0 && amounts[1] == 0) revert NoNonZeroAmountProvided();

        (MaverickDeploymentExtraParams memory maverickExtraParams) =
            abi.decode(extraParams, (MaverickDeploymentExtraParams));

        _approveTokens(router, maverickExtraParams);

        (uint256 receivingTokenId, uint256 tokenAAmount, uint256 tokenBAmount, IPool.BinDelta[] memory binDeltas) =
        router.addLiquidityToPool(
            IPool(maverickExtraParams.poolAddress),
            maverickExtraParams.tokenId,
            maverickExtraParams.maverickParams,
            amounts[0],
            amounts[1],
            maverickExtraParams.deadline
        );

        // Collect deployed bins data
        (
            uint256 binslpAmountSummary,
            uint256 binslpBalanceSummary,
            uint256 binsLpTotalSupplySummary,
            uint256[] memory deployedBinIds
        ) = _collectBinSummary(binDeltas, IPool(maverickExtraParams.poolAddress), maverickExtraParams.tokenId);

        if (binslpAmountSummary < minLpMintAmount) revert MinLpAmountNotReached();
        if (tokenAAmount < amounts[0]) revert InvalidBalanceChange();
        if (tokenBAmount < amounts[1]) revert InvalidBalanceChange();

        emit DeployLiquidity(
            [tokenAAmount, tokenBAmount],
            [
                address(IPool(maverickExtraParams.poolAddress).tokenA()),
                address(IPool(maverickExtraParams.poolAddress).tokenB())
            ],
            [binslpAmountSummary, binslpBalanceSummary, binsLpTotalSupplySummary],
            maverickExtraParams.poolAddress,
            receivingTokenId,
            deployedBinIds
        );
    }

    /**
     * @notice Withdraws liquidity from Maverick
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param router Maverick Router contract
     * @param amounts quantity of tokens to withdraw
     * @param maxLpBurnAmount max amount of LP tokens to burn for withdrawal
     * @param extraParams encoded `MaverickWithdrawalExtraParams`
     */
    function removeLiquidity(
        IRouter router,
        uint256[] calldata amounts,
        uint256 maxLpBurnAmount,
        bytes calldata extraParams
    ) external returns (uint256[] memory actualAmounts) {
        //slither-disable-start reentrancy-events
        if (maxLpBurnAmount == 0) revert MustBeMoreThanZero();
        if (amounts.length != 2) revert ArraysLengthMismatch();
        if (amounts[0] == 0 && amounts[1] == 0) revert NoNonZeroAmountProvided();

        (MaverickWithdrawalExtraParams memory maverickExtraParams) =
            abi.decode(extraParams, (MaverickWithdrawalExtraParams));

        router.position().approve(address(router), maverickExtraParams.tokenId);

        (uint256 tokenAAmount, uint256 tokenBAmount, IPool.BinDelta[] memory binDeltas) =
            _runWithdrawal(router, amounts, maverickExtraParams);

        // Collect deployed bins data
        (
            uint256 binslpAmountSummary,
            uint256 binslpBalanceSummary,
            uint256 binsLpTotalSupplySummary,
            uint256[] memory deployedBinIds
        ) = _collectBinSummary(binDeltas, IPool(maverickExtraParams.poolAddress), maverickExtraParams.tokenId);

        if (binslpAmountSummary > maxLpBurnAmount) revert LpTokenAmountMismatch();
        if (tokenAAmount < amounts[0]) revert InvalidBalanceChange();
        if (tokenBAmount < amounts[1]) revert InvalidBalanceChange();

        actualAmounts = new uint256[](2);
        actualAmounts[0] = tokenAAmount;
        actualAmounts[1] = tokenBAmount;

        emit WithdrawLiquidity(
            [tokenAAmount, tokenBAmount],
            [
                address(IPool(maverickExtraParams.poolAddress).tokenA()),
                address(IPool(maverickExtraParams.poolAddress).tokenB())
            ],
            [binslpAmountSummary, binslpBalanceSummary, binsLpTotalSupplySummary],
            maverickExtraParams.poolAddress,
            maverickExtraParams.tokenId,
            deployedBinIds
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Encodes the provided parameters into a byte array
     * @dev This function helps in building extraParams with dynamic values when using the Solver SDK
     * @param poolAddress The address of the pool
     * @param tokenId The ID of the token
     * @param deadline The deadline for the operation
     * @param maverickParams An array of AddLiquidityParams parameters
     * @return The encoded parameters as a byte array
     */
    function buildExtraParams(
        address poolAddress,
        uint256 tokenId,
        uint256 deadline,
        IPool.AddLiquidityParams[] memory maverickParams
    ) external pure returns (bytes memory) {
        return abi.encode(MaverickDeploymentExtraParams(poolAddress, tokenId, deadline, maverickParams));
    }

    /**
     * @notice Creates a new AddLiquidityParams structure
     * @dev This function helps in building extraParams with dynamic values when using the Solver SDK
     * @param kind The kind of the parameter
     * @param pos The position of the parameter
     * @param isDelta Boolean flag indicating if it's a delta
     * @param deltaA The delta A value
     * @param deltaB The delta B value
     * @return A new AddLiquidityParams structure
     */
    function buildMaverickParams(
        uint8 kind,
        int32 pos,
        bool isDelta,
        uint128 deltaA,
        uint128 deltaB
    ) external pure returns (IPool.AddLiquidityParams memory) {
        return IPool.AddLiquidityParams(kind, pos, isDelta, deltaA, deltaB);
    }

    ///@dev Adoiding stack-too-deep-errors
    function _runWithdrawal(
        IRouter router,
        uint256[] calldata amounts,
        MaverickWithdrawalExtraParams memory maverickExtraParams
    ) private returns (uint256 tokenAAmount, uint256 tokenBAmount, IPool.BinDelta[] memory binDeltas) {
        (tokenAAmount, tokenBAmount, binDeltas) = router.removeLiquidity(
            IPool(maverickExtraParams.poolAddress),
            address(this),
            maverickExtraParams.tokenId,
            maverickExtraParams.maverickParams,
            amounts[0],
            amounts[1],
            maverickExtraParams.deadline
        );
    }

    function _approveTokens(IRouter router, MaverickDeploymentExtraParams memory maverickExtraParams) private {
        IPool.AddLiquidityParams[] memory maverickParams = maverickExtraParams.maverickParams;

        uint256[] memory approvalSummary = new uint256[](2);
        for (uint256 i = 0; i < maverickParams.length; ++i) {
            approvalSummary[0] += maverickParams[i].deltaA;
            approvalSummary[1] += maverickParams[i].deltaB;
        }
        LibAdapter._approve(IPool(maverickExtraParams.poolAddress).tokenA(), address(router), approvalSummary[0]);
        LibAdapter._approve(IPool(maverickExtraParams.poolAddress).tokenB(), address(router), approvalSummary[1]);
    }

    function _collectBinSummary(
        IPool.BinDelta[] memory binDeltas,
        IPool pool,
        uint256 tokenId
    )
        private
        view
        returns (
            uint256 binslpAmountSummary,
            uint256 binslpBalanceSummary,
            uint256 binsLpTotalSupplySummary,
            uint256[] memory affectedBinIds
        )
    {
        affectedBinIds = new uint256[](binDeltas.length);
        for (uint256 i = 0; i < binDeltas.length; ++i) {
            IPool.BinDelta memory bin = binDeltas[i];
            affectedBinIds[i] = bin.binId;
            binslpAmountSummary += bin.deltaLpBalance;
            binslpBalanceSummary += pool.balanceOf(tokenId, bin.binId);
            binsLpTotalSupplySummary += pool.getBin(bin.binId).totalSupply;
        }
    }
}
//slither-disable-end similar-names
