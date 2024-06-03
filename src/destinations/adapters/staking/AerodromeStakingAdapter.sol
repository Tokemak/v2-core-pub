// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IAerodromeGauge } from "src/interfaces/external/aerodrome/IAerodromeGauge.sol";

import { LibAdapter } from "src/libs/LibAdapter.sol";
import { Errors } from "src/utils/Errors.sol";

library AerodromeStakingAdapter {
    event DeployLiquidity(
        uint256 amountDeposited,
        address stakingToken,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress
    );

    event WithdrawLiquidity(
        uint256 amountsWithdrawn,
        address stakingToken,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress
    );

    error MinLpAmountNotReached();
    error LpTokenAmountMismatch();

    /**
     * @notice Stakes tokens to Aerodrome
     * @dev Calls to external contract
     * @param amount number of LP tokens to stake
     * @param minLpMintAmount min amount to reach in result of staking LPs
     * @param pool corresponding pool of the deposited token
     */
    function stakeLPs(IVoter voter, uint256 amount, uint256 minLpMintAmount, address pool) public {
        Errors.verifyNotZero(address(voter), "voter");
        Errors.verifyNotZero(amount, "amount");
        Errors.verifyNotZero(minLpMintAmount, "minLpMintAmount");
        Errors.verifyNotZero(pool, "pool");
        //slither-disable-start reentrancy-events

        address gaugeAddress = voter.gauges(pool);
        Errors.verifyNotZero(gaugeAddress, "gaugeAddress");
        IAerodromeGauge gauge = IAerodromeGauge(gaugeAddress);

        uint256 lpTokensBefore = gauge.balanceOf(address(this));

        address stakingToken = gauge.stakingToken();
        Errors.verifyNotZero(stakingToken, "stakingToken");

        LibAdapter._approve(IERC20(stakingToken), address(gauge), amount);

        gauge.deposit(amount);

        uint256 lpTokensAfter = gauge.balanceOf(address(this));
        uint256 lpTokenAmount = lpTokensAfter - lpTokensBefore;
        if (lpTokenAmount < minLpMintAmount) revert MinLpAmountNotReached();

        emit DeployLiquidity(
            amount, stakingToken, [lpTokenAmount, lpTokensAfter, gauge.totalSupply()], pool, address(gauge)
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Unstakes tokens from Aerodrome
     * @dev Calls to external contract
     * @param amount number of corresponding LP token to withdraw
     * @param maxLpBurnAmount max amount to burn in result of unstaking LPs
     * @param pool corresponding pool of the deposited tokens
     */
    function unstakeLPs(IVoter voter, uint256 amount, uint256 maxLpBurnAmount, address pool) public {
        Errors.verifyNotZero(address(voter), "voter");
        Errors.verifyNotZero(amount, "amount");
        Errors.verifyNotZero(maxLpBurnAmount, "maxLpBurnAmount");
        Errors.verifyNotZero(pool, "pool");
        //slither-disable-start reentrancy-events

        address gaugeAddress = voter.gauges(pool);
        Errors.verifyNotZero(gaugeAddress, "gaugeAddress");
        IAerodromeGauge gauge = IAerodromeGauge(gaugeAddress);

        address stakingToken = gauge.stakingToken();
        Errors.verifyNotZero(stakingToken, "stakingToken");

        uint256 lpTokensBefore = gauge.balanceOf(address(this));

        gauge.withdraw(amount);

        uint256 lpTokensAfter = gauge.balanceOf(address(this));

        uint256 lpTokenAmount = lpTokensBefore - lpTokensAfter;
        if (lpTokenAmount > maxLpBurnAmount) revert LpTokenAmountMismatch();

        emit WithdrawLiquidity(
            amount, stakingToken, [lpTokenAmount, lpTokensAfter, gauge.totalSupply()], pool, address(gauge)
        );
        //slither-disable-end reentrancy-events
    }
}
