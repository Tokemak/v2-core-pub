// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { BaseOracleDenominations, ISystemRegistry } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOffchainAggregator } from "src/interfaces/external/chainlink/IOffchainAggregator.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title Gets the value of tokens that Chainlink provides a feed for.
 * @dev Many Chainlink feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract ChainlinkOracle is BaseOracleDenominations {
    /**
     * @notice Used to store info on token's Chainlink feed.
     * @param oracle Address of Chainlink oracle for token mapped.
     * @param pricingTimeout Custom timeout for asset pricing.  If 0, contract will use
     *      default defined in `BaseOracleDenominations.sol`.
     * @param denomination Enum representing what token mapped is denominated in.
     * @param decimals Number of decimal precision that oracle returns.  Can differ from
     *      token decimals in some cases.
     */
    struct ChainlinkInfo {
        IAggregatorV3Interface oracle;
        uint32 pricingTimeout;
        Denomination denomination;
        uint8 decimals;
    }

    /// @dev Mapping of token to ChainlinkInfo struct.  Private to enforce zero address checks.
    mapping(address => ChainlinkInfo) private chainlinkOracleInfo;

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

    constructor(ISystemRegistry _systemRegistry) BaseOracleDenominations(_systemRegistry) { }

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
        Errors.verifyNotZero(token, "tokenToAddOracle");
        Errors.verifyNotZero(address(chainlinkOracle), "oracle");
        if (address(chainlinkOracleInfo[token].oracle) != address(0)) revert Errors.MustBeZero();

        uint8 oracleDecimals = chainlinkOracle.decimals();
        chainlinkOracleInfo[token] = ChainlinkInfo({
            oracle: chainlinkOracle,
            denomination: denomination,
            decimals: oracleDecimals,
            pricingTimeout: pricingTimeout
        });

        emit ChainlinkRegistrationAdded(token, address(chainlinkOracle), denomination, oracleDecimals);
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     */
    function removeChainlinkRegistration(address token) external onlyOwner {
        Errors.verifyNotZero(token, "tokenToRemoveOracle");
        address oracleBeforeDeletion = address(chainlinkOracleInfo[token].oracle);
        if (oracleBeforeDeletion == address(0)) revert Errors.MustBeSet();
        delete chainlinkOracleInfo[token];
        emit ChainlinkRegistrationRemoved(token, oracleBeforeDeletion);
    }

    /**
     * @notice Returns `ChainlinkInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     */
    function getChainlinkInfo(address token) external view returns (ChainlinkInfo memory) {
        return chainlinkOracleInfo[token];
    }

    // slither-disable-start timestamp
    function getPriceInEth(address token) external returns (uint256) {
        ChainlinkInfo memory chainlinkOracle = _getChainlinkInfo(token);

        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 price,, uint256 updatedAt,) = chainlinkOracle.oracle.latestRoundData();
        uint256 timestamp = block.timestamp;
        uint256 oracleStoredTimeout = uint256(chainlinkOracle.pricingTimeout);
        uint256 tokenPricingTimeout = oracleStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : oracleStoredTimeout;

        if (price <= 0) revert InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        IOffchainAggregator aggregator = IOffchainAggregator(chainlinkOracle.oracle.aggregator());

        if (
            roundId == 0 || updatedAt == 0 || updatedAt > timestamp || updatedAt < timestamp - tokenPricingTimeout
                || priceUint == uint256(int256(aggregator.maxAnswer()))
                || priceUint == uint256(int256(aggregator.minAnswer()))
        ) revert InvalidDataReturned();

        uint256 decimals = chainlinkOracle.decimals;
        // Chainlink feeds have certain decimal precisions, does not neccessarily conform to underlying asset.
        uint256 normalizedPrice = decimals == 18 ? priceUint : priceUint * 10 ** (18 - decimals);

        return _denominationPricing(chainlinkOracle.denomination, normalizedPrice, token);
    }
    // slither-disable-end timestamp

    /// @dev internal getter to access `tokenToChainlinkOracle` mapping, enforces address(0) check.
    function _getChainlinkInfo(address token) internal view returns (ChainlinkInfo memory chainlinkInfo) {
        chainlinkInfo = chainlinkOracleInfo[token];
        Errors.verifyNotZero(address(chainlinkInfo.oracle), "chainlinkOracle");
    }
}
