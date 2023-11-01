// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { BaseOracleDenominations, ISystemRegistry } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IEthValueOracle } from "src/interfaces/pricing/IEthValueOracle.sol";
import { Errors } from "src/utils/Errors.sol";

import { UsingTellor } from "usingtellor/UsingTellor.sol";

/**
 * @title Gets the spot price of tokens that Tellor provides a feed for.
 * @dev Will convert all tokens to Eth pricing regardless of original denomination.
 * @dev Returns 18 decimals of precision.
 */
contract TellorOracle is BaseOracleDenominations, UsingTellor {
    /// @dev Thrown when an invalid pricing timeout is submitted at oracle registration.
    error InvalidPricingTimeout(uint256 pricingTimeout);

    /**
     * @notice Used to store information about Tellor price queries.
     * @dev No decimals, all returned in e18 precision.
     * @param queryId bytes32 queryId for pricing query. See here: https://tellor.io/queryidstation/.
     * @param pricingTimeout Custom timeout for asset.  If 0, contract will use default defined in
     *    `BaseOracleDenominations.sol`.
     * @param denomination Enum representing denomination of price returned.
     */
    struct TellorInfo {
        bytes32 queryId;
        uint32 pricingTimeout;
        Denomination denomination;
    }

    /// @dev Minimum time to have passed since price submitted to Tellor.
    uint256 public constant TELLOR_PRICING_FRESHNESS = 15 minutes;

    /// @dev Token address to TellorInfo structs.
    mapping(address => TellorInfo) private tellorQueryInfo;

    /// @notice Emitted when information about a Tellor query is registered.
    event TellorRegistrationAdded(address token, Denomination denomination, bytes32 _queryId);

    /// @notice Emitted when  information about a Tellor query is removed.
    event TellorRegistrationRemoved(address token, bytes32 queryId);

    constructor(
        ISystemRegistry _systemRegistry,
        address _tellorOracleAddress
    )
        // Tellor requires payable address
        UsingTellor(payable(_tellorOracleAddress))
        BaseOracleDenominations(_systemRegistry)
    {
        Errors.verifyNotZero(_tellorOracleAddress, "tellor");
    }

    /**
     * @notice Allows permissioned address to set _queryId, denomination for token address.
     * @param token Address of token to set queryId for.
     * @param _queryId Bytes32 queryId.
     * @param denomination Denomination of token.
     * @param pricingTimeout Custom timeout for queryId if needed.  Can be set to zero
     *      to use default defined in `BaseOracleDenominations.sol`.
     */
    function addTellorRegistration(
        address token,
        bytes32 _queryId,
        Denomination denomination,
        uint32 pricingTimeout
    ) external onlyOwner {
        Errors.verifyNotZero(token, "tokenForQueryId");
        Errors.verifyNotZero(_queryId, "queryId");
        if (tellorQueryInfo[token].queryId != bytes32(0)) revert Errors.MustBeZero();
        if (pricingTimeout != 0 && pricingTimeout < TELLOR_PRICING_FRESHNESS) {
            revert InvalidPricingTimeout(pricingTimeout);
        }
        tellorQueryInfo[token] =
            TellorInfo({ queryId: _queryId, denomination: denomination, pricingTimeout: pricingTimeout });
        emit TellorRegistrationAdded(token, denomination, _queryId);
    }

    /**
     * @notice Allows permissioned removal registration for token address.
     * @param token Token to remove TellorInfo struct for.
     */
    function removeTellorRegistration(address token) external onlyOwner {
        Errors.verifyNotZero(token, "tokenToRemoveRegistration");
        bytes32 queryIdBeforeDeletion = tellorQueryInfo[token].queryId;
        Errors.verifyNotZero(queryIdBeforeDeletion, "queryIdBeforeDeletion");
        delete tellorQueryInfo[token];
        emit TellorRegistrationRemoved(token, queryIdBeforeDeletion);
    }

    /**
     * @notice External function to view TellorInfo struct for token address.
     * @dev Will return empty struct for unregistered token address.
     * @param token Address of token to view TellorInfo struct for.
     */
    function getQueryInfo(address token) external view returns (TellorInfo memory) {
        return tellorQueryInfo[token];
    }

    /**
     * @dev Tellor always returns prices with 18 decimals of precision for spot pricing, so we do not need
     *      to worry about increasing or decreasing precision here.  See here:
     *      https://github.com/tellor-io/dataSpecs/blob/main/types/SpotPrice.md
     */
    // slither-disable-start timestamp
    function getPriceInEth(address tokenToPrice) external returns (uint256) {
        TellorInfo memory tellorInfo = _getQueryInfo(tokenToPrice);
        uint256 timestamp = block.timestamp;
        uint256 tellorMaxAllowableTimestamp = timestamp - TELLOR_PRICING_FRESHNESS;

        // Giving time for Tellor network to dispute price
        (bytes memory value, uint256 timestampRetrieved) =
            getDataBefore(tellorInfo.queryId, tellorMaxAllowableTimestamp);
        uint256 tellorStoredTimeout = uint256(tellorInfo.pricingTimeout);
        uint256 tokenPricingTimeout = tellorStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : tellorStoredTimeout;
        uint256 price = abi.decode(value, (uint256));

        // Check that something was returned and freshness of price.
        if (
            timestampRetrieved == 0 || timestamp - timestampRetrieved > tokenPricingTimeout
                || timestampRetrieved >= tellorMaxAllowableTimestamp || price == 0
        ) {
            revert InvalidDataReturned();
        }

        return _denominationPricing(tellorInfo.denomination, price, tokenToPrice);
    }
    // slither-disable-end timestamp

    /// @dev Used to enforce non-existent queryId checks
    function _getQueryInfo(address token) private view returns (TellorInfo memory tellorInfo) {
        tellorInfo = tellorQueryInfo[token];
        Errors.verifyNotZero(tellorInfo.queryId, "queryId");
    }
}
