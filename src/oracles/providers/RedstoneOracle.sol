// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import {
    BaseAggregatorV3OracleInformation,
    ISystemRegistry
} from "src/oracles/providers/base/BaseAggregatorV3OracleInformation.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title Gets the value of tokens that Redstone provides a feed for.
 * @dev Many Redstone feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract RedstoneOracle is BaseAggregatorV3OracleInformation {
    constructor(ISystemRegistry _systemRegistry) BaseAggregatorV3OracleInformation(_systemRegistry) { }

    /**
     * @notice Returns `RedStoneInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     * @return RedstoneInfo struct with pricing information and oracle on token.
     */
    function getRedstoneInfo(address token) external view returns (OracleInfo memory) {
        return BaseAggregatorV3OracleInformation.getOracleInfo(token);
    }

    /**
     * @notice Fetches the price of a token in ETH denomination.
     * @param token Address of token.
     * @return priceInEth Price of token in ETH.
     */
    function getPriceInEth(address token) external returns (uint256 priceInEth) {
        OracleInfo memory oracleInfo = _getOracleInfo(token);
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 updatedAt,) = oracleInfo.oracle.latestRoundData();
        priceInEth = BaseAggregatorV3OracleInformation._getPriceInEth(token, oracleInfo, price, updatedAt);
    }
}
