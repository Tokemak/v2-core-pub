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
     * @notice Validates the price returned by oracle.
     * @dev This function only needs to be invoked for oracles which implement IOffchainAggregator.
     * @param oracleInfo OracleInfo of the token being validated.
     * @param roundId Round ID of the price obtained from oracle.
     * @param price Price obtained from oracle.
     */
    function _validateOffchainAggregator(OracleInfo memory oracleInfo, uint80 roundId, int256 price) internal view {
        if (price <= 0) revert InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        IOffchainAggregator aggregator = IOffchainAggregator(oracleInfo.oracle.aggregator());

        if (
            roundId == 0 || priceUint == uint256(int256(aggregator.maxAnswer()))
                || priceUint == uint256(int256(aggregator.minAnswer()))
        ) revert InvalidDataReturned();
    }

    /**
     * @notice Fetches the price of a token in ETH denomination.
     * @param token Address of token.
     * @return priceInEth Price of token in ETH.
     */
    function getPriceInEth(address token) external returns (uint256 priceInEth) {
        OracleInfo memory oracleInfo = _getOracleInfo(token);
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 price,, uint256 updatedAt,) = oracleInfo.oracle.latestRoundData();
        _validateOffchainAggregator(oracleInfo, roundId, price);
        priceInEth = BaseAggregatorV3OracleInformation._getPriceInEth(token, oracleInfo, price, updatedAt);
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
