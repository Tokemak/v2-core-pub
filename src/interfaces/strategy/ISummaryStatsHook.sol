// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { IAutopoolStrategy } from "src/interfaces/strategy/IAutopoolStrategy.sol";

/// @title An interface for hooks for IStrategy.SummaryStats manipulations
interface ISummaryStatsHook {
    /**
     * @notice Used to execute hook that will modify IStrategy.SummaryStats struct
     * @param stats IStrategy.SummaryStats struct for destination stats
     * @param autoPool Address of autopool that rebalance is happening for
     * @param destAddress Address of destination
     * @param price -
     * @param direction Rebalance direction, in or out
     * @param amount -
     * @return IStrategy.SummaryStats struct, manipulated by hook
     */
    function execute(
        IStrategy.SummaryStats memory stats,
        IAutopool autoPool,
        address destAddress,
        uint256 price,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory);
}
