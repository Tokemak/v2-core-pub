// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IDestinationVault } from "../vault/IDestinationVault.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

interface IStrategy {
    /* ******************************** */
    /*      Events                      */
    /* ******************************** */
    event DestinationVaultAdded(address destination);
    event DestinationVaultRemoved(address destination);
    event WithdrawalQueueSet(address[] destinations);
    event AddedToRemovalQueue(address destination);
    event RemovedFromRemovalQueue(address destination);

    error InvalidDestinationVault();

    error RebalanceFailed(string message);

    /// @notice gets the list of supported destination vaults for the LMP/Strategy
    /// @return _destinations List of supported destination vaults
    function getDestinations() external view returns (address[] memory _destinations);

    /// @notice add supported destination vaults for the LMP/Strategy
    /// @param _destinations The list of destination vaults to add
    function addDestinations(address[] calldata _destinations) external;

    /// @notice remove supported destination vaults for the LMP/Strategy
    /// @param _destinations The list of destination vaults to remove
    function removeDestinations(address[] calldata _destinations) external;

    /// @param destinationIn The address / lp token of the destination vault that will increase
    /// @param tokenIn The address of the underlyer token that will be provided by the swapper
    /// @param amountIn The amount of the underlying LP tokens that will be received
    /// @param destinationOut The address of the destination vault that will decrease
    /// @param tokenOut The address of the underlyer token that will be received by the swapper
    /// @param amountOut The amount of the tokenOut that will be received by the swapper
    struct RebalanceParams {
        address destinationIn;
        address tokenIn;
        uint256 amountIn;
        address destinationOut;
        address tokenOut;
        uint256 amountOut;
    }

    /// @notice rebalance the LMP from the tokenOut (decrease) to the tokenIn (increase)
    function rebalance(RebalanceParams memory params) external;

    /// @notice rebalance the LMP from the tokenOut (decrease) to the tokenIn (increase)
    /// This uses a flash loan to receive the tokenOut to reduce the working capital requirements of the swapper
    /// @param receiver The contract receiving the tokens, needs to implement the
    /// `onFlashLoan(address user, address token, uint256 amount, uint256 fee, bytes calldata)` interface
    /// @param params Parameters by which to perform the rebalance
    /// @param data A data parameter to be passed on to the `receiver` for any custom use
    function flashRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams calldata params,
        bytes calldata data
    ) external;

    /// @notice verify that a rebalance (swap between destinations) meets all the strategy constraints
    /// @param destinationIn The address of the destination vault that will increase
    /// @param tokenIn The address of the destination vault token that will be provided by the swapper
    /// @param amountIn The amount of the tokenIn that will be provided by the swapper
    /// @param destinationOut The address of the destination vault that will decrease
    /// @param tokenOut The address of the destination vault token that will be received by the swapper
    /// @param amountOut The amount of the tokenOut that will be received by the swapper
    function verifyRebalance(
        address destinationIn,
        address tokenIn,
        uint256 amountIn,
        address destinationOut,
        address tokenOut,
        uint256 amountOut
    ) external view returns (bool success, string memory message);
}
