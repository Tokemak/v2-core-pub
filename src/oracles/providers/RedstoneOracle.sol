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
    /**
     * @notice Emitted when a token has an oracle address set.
     * @param token Address of token.
     * @param redstoneOracle Address of redstone oracle contract.
     * @param denomination Enum representing denomination.
     * @param decimals Number of decimals precision that oracle returns.
     */
    event RedstoneRegistrationAdded(address token, address redstoneOracle, Denomination denomination, uint8 decimals);

    /**
     * @notice Emitted when token to RedStone oracle mapping deleted.
     * @param token Address of token.
     * @param redstoneOracle Address of oracle.
     */
    event RedstoneRegistrationRemoved(address token, address redstoneOracle);

    constructor(ISystemRegistry _systemRegistry) BaseAggregatorV3OracleInformation(_systemRegistry) { }

    /**
     * @notice Allows oracle address and denominations to be set for token.
     * @param token Address of token for which oracle will be set.
     * @param redstoneOracle Address of oracle to be set.
     * @param denomination Address of denomination to be set.
     * @param pricingTimeout Custom timeout for price feed if desired.  Can be set to
     *      zero to use default defined in `BaseOracleDenominations.sol`.
     */
    function registerRedstoneOracle(
        address token,
        IAggregatorV3Interface redstoneOracle,
        Denomination denomination,
        uint32 pricingTimeout
    ) external onlyOwner {
        BaseAggregatorV3OracleInformation.registerOracle(token, redstoneOracle, denomination, pricingTimeout);
        uint8 oracleDecimals = redstoneOracle.decimals();

        emit RedstoneRegistrationAdded(token, address(redstoneOracle), denomination, oracleDecimals);
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     */
    function removeRedstoneRegistration(address token) external onlyOwner {
        address oracleBeforeDeletion = BaseAggregatorV3OracleInformation.removeOracleRegistration(token);
        emit RedstoneRegistrationRemoved(token, oracleBeforeDeletion);
    }

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
     * @return price Price of token in ETH.
     */
    function getPriceInEth(address token) external returns (uint256 price) {
        price = BaseAggregatorV3OracleInformation._getPriceInEth(token);
    }
}
