// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { BaseOracleDenominations, ISystemRegistry } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOffchainAggregator } from "src/interfaces/external/chainlink/IOffchainAggregator.sol";
import { Errors } from "src/utils/Errors.sol";

abstract contract BaseAggregatorV3OracleInformation is BaseOracleDenominations {
    /**
     * @notice Used to store info on token's oracle feed.
     * @param oracle Address of oracle for token mapped.
     * @param pricingTimeout Custom timeout for asset pricing.  If 0, contract will use
     *      default defined in `BaseOracleDenominations.sol`.
     * @param denomination Enum representing what token mapped is denominated in.
     * @param decimals Number of decimal precision that oracle returns.  Can differ from
     *      token decimals in some cases.
     */
    struct OracleInfo {
        IAggregatorV3Interface oracle;
        uint32 pricingTimeout;
        Denomination denomination;
        uint8 decimals;
    }

    /// @dev Mapping of token to OracleInfo struct.  Private to enforce zero address checks.
    mapping(address => OracleInfo) private tokentoOracle;

    constructor(ISystemRegistry _systemRegistry) BaseOracleDenominations(_systemRegistry) { }

    /**
     * @notice Allows oracle address and denominations to be set for token.
     * @param token Address of token for which oracle will be set.
     * @param oracle Address of oracle to be set.
     * @param denomination Address of denomination to be set.
     * @param pricingTimeout Custom timeout for price feed if desired.  Can be set to
     *      zero to use default defined in `BaseOracleDenominations.sol`.
     */
    function registerOracle(
        address token,
        IAggregatorV3Interface oracle,
        Denomination denomination,
        uint32 pricingTimeout
    ) public onlyOwner {
        Errors.verifyNotZero(token, "tokenToAddOracle");
        Errors.verifyNotZero(address(oracle), "oracle");
        if (address(tokentoOracle[token].oracle) != address(0)) revert Errors.AlreadyRegistered(token);

        uint8 oracleDecimals = oracle.decimals();
        tokentoOracle[token] = OracleInfo({
            oracle: oracle,
            denomination: denomination,
            decimals: oracleDecimals,
            pricingTimeout: pricingTimeout
        });
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     * @return oracleBeforeDeletion Address of oracle for 'token' before deletion.
     */
    function removeOracleRegistration(address token) public onlyOwner returns (address oracleBeforeDeletion) {
        Errors.verifyNotZero(token, "tokenToRemoveOracle");
        oracleBeforeDeletion = address(tokentoOracle[token].oracle);
        if (oracleBeforeDeletion == address(0)) revert Errors.MustBeSet();
        delete tokentoOracle[token];
    }

    /**
     * @notice Returns `OracleInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     * @return OracleInfo struct with information on `address token`.
     */
    function getOracleInfo(address token) public view returns (OracleInfo memory) {
        return tokentoOracle[token];
    }

    /**
     * @notice Validates the price returned by oracle.
     * @dev This function only needs to be invoked for oracles which implement IOffchainAggregator.
     * @param token Address of token to get info for.
     */
    function _validateOffchainAggregator(address token) internal view {
        Errors.verifyNotZero(token, "token");
        OracleInfo memory oracleInfo = _getOracleInfo(token);
        // slither-disable-next-line unused-return
        (, int256 price,,,) = oracleInfo.oracle.latestRoundData();

        if (price <= 0) revert InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        IOffchainAggregator aggregator = IOffchainAggregator(oracleInfo.oracle.aggregator());

        if (
            priceUint == uint256(int256(aggregator.maxAnswer())) || priceUint == uint256(int256(aggregator.minAnswer()))
        ) revert InvalidDataReturned();
    }

    // slither-disable-start timestamp
    function _getPriceInEth(address token) internal returns (uint256) {
        OracleInfo memory oracleInfo = _getOracleInfo(token);

        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 updatedAt,) = oracleInfo.oracle.latestRoundData();
        uint256 timestamp = block.timestamp;
        uint256 oracleStoredTimeout = uint256(oracleInfo.pricingTimeout);
        uint256 tokenPricingTimeout = oracleStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : oracleStoredTimeout;

        if (price <= 0) revert InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        if (updatedAt == 0 || updatedAt > timestamp || updatedAt < timestamp - tokenPricingTimeout) {
            revert InvalidDataReturned();
        }
        uint256 decimals = oracleInfo.decimals;
        // Redstone feeds have certain decimal precisions, does not neccessarily conform to underlying asset.
        uint256 normalizedPrice = decimals <= 18 ? priceUint * 10 ** (18 - decimals) : priceUint / 10 ** (decimals - 18);

        return _denominationPricing(oracleInfo.denomination, normalizedPrice, token);
    }
    // slither-disable-end timestamp

    /// @dev internal getter to access `tokenToOracle` mapping, enforces address(0) check.
    function _getOracleInfo(address token) internal view returns (OracleInfo memory oracleInfo) {
        oracleInfo = tokentoOracle[token];
        Errors.verifyNotZero(address(oracleInfo.oracle), "Oracle");
    }
}
