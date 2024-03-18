// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import {
    BaseAggregatorV3OracleInformation,
    ISystemRegistry
} from "src/oracles/providers/base/BaseAggregatorV3OracleInformation.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOffchainAggregator } from "src/interfaces/external/chainlink/IOffchainAggregator.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title Gets the value of tokens that Chainlink provides a feed for.
 * @dev Many Chainlink feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract ChainlinkOracle is BaseAggregatorV3OracleInformation {
    /**
     * @notice Emitted when a token has an oracle address set.
     * @param token Address of token.
     * @param chainlinkOracle Address of chainlink oracle contract.
     * @param denomination Enum representing denomination.
     * @param decimals Number of decimals precision that oracle returns.
     */
    event ChainlinkRegistrationAdded(address token, address chainlinkOracle, Denomination denomination, uint8 decimals);

    /**
     * @notice Emitted when token to Chainlink oracle mapping deleted.
     * @param token Address of token.
     * @param chainlinkOracle Address of oracle.
     */
    event ChainlinkRegistrationRemoved(address token, address chainlinkOracle);

    constructor(ISystemRegistry _systemRegistry) BaseAggregatorV3OracleInformation(_systemRegistry) { }

    /**
     * @notice Allows oracle address and denominations to be set for token.
     * @param token Address of token for which oracle will be set.
     * @param chainlinkOracle Address of oracle to be set.
     * @param denomination Address of denomination to be set.
     * @param pricingTimeout Custom timeout for price feed if desired.  Can be set to
     *      zero to use default defined in `BaseOracleDenominations.sol`.
     */
    function registerChainlinkOracle(
        address token,
        IAggregatorV3Interface chainlinkOracle,
        Denomination denomination,
        uint32 pricingTimeout
    ) external onlyOwner {
        BaseAggregatorV3OracleInformation.registerOracle(token, chainlinkOracle, denomination, pricingTimeout);
        uint8 oracleDecimals = chainlinkOracle.decimals();

        emit ChainlinkRegistrationAdded(token, address(chainlinkOracle), denomination, oracleDecimals);
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     */
    function removeChainlinkRegistration(address token) external onlyOwner {
        address oracleBeforeDeletion = BaseAggregatorV3OracleInformation.removeOracleRegistration(token);
        emit ChainlinkRegistrationRemoved(token, oracleBeforeDeletion);
    }

    /**
     * @notice Fetches the price of a token in ETH denomination.
     * @param token Address of token.
     * @return price Price of token in ETH.
     */
    function getPriceInEth(address token) external returns (uint256 price) {
        BaseAggregatorV3OracleInformation._validateOffchainAggregator(token);
        price = BaseAggregatorV3OracleInformation._getPriceInEth(token);
    }

    /**
     * @notice Returns `OracleInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     * @return OracleInfo struct with pricing information and oracle on token.
     */
    function getChainlinkInfo(address token) external view returns (OracleInfo memory) {
        return BaseAggregatorV3OracleInformation.getOracleInfo(token);
    }
}
