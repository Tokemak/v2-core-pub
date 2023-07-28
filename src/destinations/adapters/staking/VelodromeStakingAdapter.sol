// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IGauge } from "src/interfaces/external/velodrome/IGauge.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { Errors } from "src/utils/Errors.sol";

library VelodromeStakingAdapter {
    event DeployLiquidity(
        uint256[] amountsDeposited,
        uint256[] tokensIds,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress,
        address staking
    );

    event WithdrawLiquidity(
        uint256[] amountsWithdrawn,
        uint256[] tokensIds,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress,
        address staking
    );

    /**
     * @notice Stakes tokens to Velodrome
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param voter Address of the Velodrome voter
     * @param amounts amounts of corresponding tokenIds to add
     * @param tokenIds ids for the associated LP tokens
     * @param minLpMintAmount min amount to reach in result of staking (for all tokens in summary)
     * @param pool corresponding pool of the deposited tokens
     */
    function stakeLPs(
        address voter,
        uint256[] calldata amounts,
        uint256[] calldata tokenIds,
        uint256 minLpMintAmount,
        address pool
    ) public {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(voter, "voter");
        Errors.verifyNotZero(minLpMintAmount, "minLpMintAmount");
        Errors.verifyNotZero(amounts.length, "amounts.length");
        Errors.verifyNotZero(tokenIds.length, "tokenIds.length");
        Errors.verifyArrayLengths(amounts.length, tokenIds.length, "amounts+tokenIds");
        Errors.verifyNotZero(pool, "pool");

        address gaugeAddress = IVoter(voter).gauges(pool);
        IGauge gauge = IGauge(gaugeAddress);

        uint256 lpTokensBefore = gauge.balanceOf(address(this));
        for (uint256 i = 0; i < amounts.length; ++i) {
            LibAdapter._approve(IERC20(gauge.stake()), address(gauge), amounts[i]);
            gauge.deposit(amounts[i], tokenIds[i]);
        }
        uint256 lpTokensAfter = gauge.balanceOf(address(this));
        uint256 lpTokenAmount = lpTokensAfter - lpTokensBefore;
        if (lpTokenAmount < minLpMintAmount) revert LibAdapter.MinLpAmountNotReached();

        emit DeployLiquidity(
            amounts,
            tokenIds,
            [lpTokenAmount, lpTokensAfter, gauge.totalSupply()],
            pool,
            address(gauge),
            address(gauge.stake())
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Unstakes tokens from Velodrome
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param voter Address of the Velodrome voter
     * @param amounts amounts of corresponding tokenIds to add
     * @param tokenIds ids for the associated LP tokens
     * @param maxLpBurnAmount max amount to burn in result of unstaking (for all tokens in summary)
     * @param pool corresponding pool of the deposited tokens
     */
    function unstakeLPs(
        address voter,
        uint256[] calldata amounts,
        uint256[] calldata tokenIds,
        uint256 maxLpBurnAmount,
        address pool
    ) public {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(voter, "voter");
        Errors.verifyNotZero(maxLpBurnAmount, "maxLpBurnAmount");
        Errors.verifyNotZero(amounts.length, "amounts.length");
        Errors.verifyNotZero(tokenIds.length, "tokenIds.length");
        Errors.verifyArrayLengths(amounts.length, tokenIds.length, "amounts+tokenIds");
        Errors.verifyNotZero(pool, "pool");

        address gaugeAddress = IVoter(voter).gauges(pool);
        IGauge gauge = IGauge(gaugeAddress);

        uint256 lpTokensBefore = gauge.balanceOf(address(this));

        for (uint256 i = 0; i < amounts.length; ++i) {
            gauge.withdrawToken(amounts[i], tokenIds[i]);
        }

        uint256 lpTokensAfter = gauge.balanceOf(address(this));

        uint256 lpTokenAmount = lpTokensBefore - lpTokensAfter;
        if (lpTokenAmount > maxLpBurnAmount) revert LibAdapter.LpTokenAmountMismatch();

        emit WithdrawLiquidity(
            amounts,
            tokenIds,
            [lpTokenAmount, lpTokensAfter, gauge.totalSupply()],
            pool,
            address(gauge),
            address(gauge.stake())
        );
        //slither-disable-end reentrancy-events
    }
}
