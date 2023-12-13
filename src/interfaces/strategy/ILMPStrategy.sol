// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";

interface ILMPStrategy {
    /// @notice verify that a rebalance (swap between destinations) meets all the strategy constraints
    /// @dev Signature identical to IStrategy.verifyRebalance
    function verifyRebalance(
        IStrategy.RebalanceParams memory,
        IStrategy.SummaryStats memory
    ) external returns (bool, string memory message);

    /// @notice called by the LMPVault when NAV is updated
    /// @dev can only be called by the strategy's registered LMPVault
    /// @param navPerShare The navPerShare to record
    function navUpdate(uint256 navPerShare) external;

    /// @notice called by the LMPVault when a rebalance is completed
    /// @dev can only be called by the strategy's registered LMPVault
    /// @param rebalanceParams The parameters for the rebalance that was executed
    function rebalanceSuccessfullyExecuted(IStrategy.RebalanceParams memory rebalanceParams) external;

    /// @notice called by the LMPVault during rebalance process
    /// @param rebalanceParams The parameters for the rebalance that was executed
    function getRebalanceOutSummaryStats(IStrategy.RebalanceParams memory rebalanceParams)
        external
        returns (IStrategy.SummaryStats memory outSummary);
}
