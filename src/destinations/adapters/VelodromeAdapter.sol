// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IRouter } from "src/interfaces/external/velodrome/IRouter.sol";
import { IPair } from "src/interfaces/external/velodrome/IPair.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { Errors } from "src/utils/Errors.sol";

library VelodromeAdapter {
    event DeployLiquidity(
        uint256[2] amountsDeposited,
        address[2] tokens,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pairAddress
    );

    event WithdrawLiquidity(
        uint256[2] amountsWithdrawn,
        address[2] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pairAddress
    );

    /**
     * @notice A struct used to pass Velodrome params
     * @dev Used to avoid stack-too-deep-errors
     * @param tokenA First pool token
     * @param tokenB Second pool token
     * @param stable A flag that indicates pool type
     * @param amountAMin Minimum amount of the first token to deposit/receive
     * @param amountBMin Minimum amount of the second token to deposit/receive
     * @param deadline Execution deadline in timestamp format
     */
    struct VelodromeExtraParams {
        address tokenA;
        address tokenB;
        bool stable;
        uint256 amountAMin;
        uint256 amountBMin;
        uint256 deadline;
    }

    /**
     * @notice Deploys liquidity to Velodrome
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param router Velodrome Router contract
     * @param amounts quantity of tokens to deposit
     * @param minLpMintAmount min amount of LP tokens to mint on deposit
     * @param velodromeExtraParams encoded `VelodromeExtraParams`
     */
    function addLiquidity(
        address router,
        uint256[] calldata amounts,
        uint256 minLpMintAmount,
        bytes calldata velodromeExtraParams
    ) public {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(router, "router");
        Errors.verifyNotZero(minLpMintAmount, "minLpMintAmount");
        if (amounts.length != 2) revert Errors.InvalidParam("amounts.length");
        if (amounts[0] == 0 && amounts[1] == 0) revert LibAdapter.NoNonZeroAmountProvided();

        (VelodromeExtraParams memory extraParams) = abi.decode(velodromeExtraParams, (VelodromeExtraParams));

        Errors.verifyNotZero(extraParams.tokenA, "extraParams.tokenA");
        Errors.verifyNotZero(extraParams.tokenB, "extraParams.tokenB");
        Errors.verifyNotZero(extraParams.deadline, "extraParams.deadline");

        LibAdapter._approve(IERC20(extraParams.tokenA), router, amounts[0]);
        LibAdapter._approve(IERC20(extraParams.tokenB), router, amounts[1]);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = IRouter(router).addLiquidity(
            extraParams.tokenA,
            extraParams.tokenB,
            extraParams.stable,
            amounts[0],
            amounts[1],
            extraParams.amountAMin,
            extraParams.amountBMin,
            address(this),
            extraParams.deadline
        );

        if (liquidity < minLpMintAmount) revert LibAdapter.MinLpAmountNotReached();
        if (amountA > amounts[0]) revert LibAdapter.InvalidBalanceChange();
        if (amountB > amounts[1]) revert LibAdapter.InvalidBalanceChange();

        IPair pair = _getPair(router, extraParams);

        emit DeployLiquidity(
            [amountA, amountB],
            [extraParams.tokenA, extraParams.tokenB],
            [liquidity, pair.balanceOf(address(this)), pair.totalSupply()],
            address(pair)
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Withdraws liquidity from Velodrome
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param router Velodrome Router contract
     * @param amounts quantity of tokens to withdraw
     * @param maxLpBurnAmount max amount of LP tokens to burn for withdrawal
     * @param velodromeExtraParams encoded `VelodromeExtraParams`
     */
    function removeLiquidity(
        address router,
        uint256[] calldata amounts,
        uint256 maxLpBurnAmount,
        bytes calldata velodromeExtraParams
    ) external returns (uint256[] memory actualAmounts) {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(router, "router");
        Errors.verifyNotZero(maxLpBurnAmount, "maxLpBurnAmount");
        if (amounts.length != 2) revert Errors.InvalidParam("amounts.length");
        if (amounts[0] == 0 && amounts[1] == 0) revert LibAdapter.NoNonZeroAmountProvided();

        (VelodromeExtraParams memory extraParams) = abi.decode(velodromeExtraParams, (VelodromeExtraParams));

        Errors.verifyNotZero(extraParams.tokenA, "extraParams.tokenA");
        Errors.verifyNotZero(extraParams.tokenB, "extraParams.tokenB");
        Errors.verifyNotZero(extraParams.deadline, "extraParams.deadline");

        IPair pair = _getPair(router, extraParams);

        LibAdapter._approve(pair, address(router), maxLpBurnAmount);

        uint256 lpTokensBefore = pair.balanceOf(address(this));

        (uint256 amountA, uint256 amountB) = _runWithdrawal(router, amounts, maxLpBurnAmount, extraParams);

        uint256 lpTokensAfter = pair.balanceOf(address(this));

        uint256 lpTokenAmount = lpTokensBefore - lpTokensAfter;
        if (lpTokenAmount > maxLpBurnAmount) {
            revert LibAdapter.LpTokenAmountMismatch();
        }
        if (amountA < amounts[0]) revert LibAdapter.InvalidBalanceChange();
        if (amountB < amounts[1]) revert LibAdapter.InvalidBalanceChange();

        actualAmounts = new uint256[](2);
        actualAmounts[0] = amountA;
        actualAmounts[1] = amountB;

        emit WithdrawLiquidity(
            [amountA, amountB],
            [extraParams.tokenA, extraParams.tokenB],
            [lpTokenAmount, lpTokensAfter, pair.totalSupply()],
            address(pair)
        );
        //slither-disable-end reentrancy-events
    }

    ///@dev This is a helper function to avoid stack-too-deep-errors
    function _runWithdrawal(
        address router,
        uint256[] calldata amounts,
        uint256 maxLpBurnAmount,
        VelodromeExtraParams memory params
    ) private returns (uint256 amountA, uint256 amountB) {
        (amountA, amountB) = IRouter(router).removeLiquidity(
            params.tokenA,
            params.tokenB,
            params.stable,
            maxLpBurnAmount,
            amounts[0],
            amounts[1],
            address(this),
            params.deadline
        );
    }

    ///@dev This is a helper function to avoid stack-too-deep-errors
    function _getPair(address router, VelodromeExtraParams memory params) private view returns (IPair pair) {
        pair = IPair(IRouter(router).pairFor(params.tokenA, params.tokenB, params.stable));
    }
}
