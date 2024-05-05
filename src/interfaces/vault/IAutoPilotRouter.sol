// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IAutoPool } from "src/interfaces/vault/IAutoPool.sol";
import { IAutoPilotRouterBase } from "src/interfaces/vault/IAutoPilotRouterBase.sol";
import { IRewards } from "src/interfaces/rewarders/IRewards.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";

/**
 * @title IAutoPilotRouter Interface
 * @notice Extends the IAutoPilotRouterBase with specific flows to save gas
 */
interface IAutoPilotRouter is IAutoPilotRouterBase {
    /**
     * ***************************   Deposit ********************************
     */

    /**
     * @notice deposit available asset balance to a AutoPoolETH.
     * @param vault The AutoPoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param minSharesOut The min amount of `vault` shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinSharesError
     */
    function depositBalance(IAutoPool vault, address to, uint256 minSharesOut) external returns (uint256 sharesOut);

    /**
     * @notice deposit max assets to a AutoPoolETH.
     * @param vault The AutoPoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param minSharesOut The min amount of `vault` shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinSharesError
     */
    function depositMax(IAutoPool vault, address to, uint256 minSharesOut) external returns (uint256 sharesOut);

    /**
     * *************************   Withdraw   **********************************
     */

    /**
     * @notice withdraw `amount` to a AutoPoolETH.
     * @param fromVault The AutoPoolETH to withdraw assets from.
     * @param toVault The AutoPoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param amount The amount of assets to withdraw from fromVault.
     * @param maxSharesIn The max amount of fromVault shares withdrawn by caller.
     * @param minSharesOut The min amount of toVault shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MaxSharesError, MinSharesError
     */
    function withdrawToDeposit(
        IAutoPool fromVault,
        IAutoPool toVault,
        address to,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) external returns (uint256 sharesOut);

    /**
     * *************************   Redeem    ********************************
     */

    /**
     * @notice redeem `shares` to a AutoPoolETH.
     * @param fromVault The AutoPoolETH to redeem shares from.
     * @param toVault The AutoPoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param shares The amount of shares to redeem from fromVault.
     * @param minSharesOut The min amount of toVault shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinAmountError, MinSharesError
     */
    function redeemToDeposit(
        IAutoPool fromVault,
        IAutoPool toVault,
        address to,
        uint256 shares,
        uint256 minSharesOut
    ) external returns (uint256 sharesOut);

    /**
     * @notice redeem max shares to a AutoPoolETH.
     * @param vault The AutoPoolETH to redeem shares from.
     * @param to The destination of assets.
     * @param minAmountOut The min amount of assets received by `to`.
     * @return amountOut the amount of assets received by `to`.
     * @dev throws MinAmountError
     */
    function redeemMax(IAutoPool vault, address to, uint256 minAmountOut) external returns (uint256 amountOut);

    /**
     * @notice swaps token
     * @param swapper Address of the swapper to use
     * @param swapParams  Parameters for the swap
     * @return amountReceived Swap output amount
     */
    function swapToken(address swapper, SwapParams memory swapParams) external returns (uint256 amountReceived);

    /**
     * @notice claims vault token rewards
     * @param rewarder Address of the rewarder to claim from
     * @param recipient Struct containing recipient details
     * @return amountReceived Swap output amount
     */
    function claimRewards(
        IRewards rewarder,
        IRewards.Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);
}
