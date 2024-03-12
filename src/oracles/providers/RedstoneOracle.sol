// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { BaseOracleDenominations, ISystemRegistry } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { Errors } from "src/utils/Errors.sol";

/**
 * @title Gets the value of tokens that Redstone provides a feed for.
 * @dev Many Redstone feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract RedstoneOracle is BaseOracleDenominations {
    /**
     * @notice Used to store info on token's RedStone feed.
     * @param oracle Address of Redstone oracle for token mapped.
     * @param pricingTimeout Custom timeout for asset pricing.  If 0, contract will use
     *      default defined in `BaseOracleDenominations.sol`.
     * @param denomination Enum representing what token mapped is denominated in.
     * @param decimals Number of decimal precision that oracle returns.  Can differ from
     *      token decimals in some cases.
     */
    struct RedstoneInfo {
        IAggregatorV3Interface oracle;
        uint32 pricingTimeout;
        Denomination denomination;
        uint8 decimals;
    }

    /// @dev Mapping of token to RedstoneInfo struct.  Private to enforce zero address checks.
    mapping(address => RedstoneInfo) private redstoneOracleInfo;

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

    constructor(ISystemRegistry _systemRegistry) BaseOracleDenominations(_systemRegistry) { }

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
        Errors.verifyNotZero(token, "tokenToAddOracle");
        Errors.verifyNotZero(address(redstoneOracle), "oracle");
        if (address(redstoneOracleInfo[token].oracle) != address(0)) revert Errors.MustBeZero();

        uint8 oracleDecimals = redstoneOracle.decimals();
        redstoneOracleInfo[token] = RedstoneInfo({
            oracle: redstoneOracle,
            denomination: denomination,
            decimals: oracleDecimals,
            pricingTimeout: pricingTimeout
        });

        emit RedstoneRegistrationAdded(token, address(redstoneOracle), denomination, oracleDecimals);
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     */
    function removeRedstoneRegistration(address token) external onlyOwner {
        Errors.verifyNotZero(token, "tokenToRemoveOracle");
        address oracleBeforeDeletion = address(redstoneOracleInfo[token].oracle);
        if (oracleBeforeDeletion == address(0)) revert Errors.MustBeSet();
        delete redstoneOracleInfo[token];
        emit RedstoneRegistrationRemoved(token, oracleBeforeDeletion);
    }

    /**
     * @notice Returns `RedStoneInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     */
    function getRedstoneInfo(address token) external view returns (RedstoneInfo memory) {
        return redstoneOracleInfo[token];
    }

    // slither-disable-start timestamp
    function getPriceInEth(address token) external returns (uint256) {
        RedstoneInfo memory redstoneOracle = _getRedstoneInfo(token);

        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 updatedAt,) = redstoneOracle.oracle.latestRoundData();
        uint256 timestamp = block.timestamp;
        uint256 oracleStoredTimeout = uint256(redstoneOracle.pricingTimeout);
        uint256 tokenPricingTimeout = oracleStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : oracleStoredTimeout;

        if (price <= 0) revert InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        if (updatedAt == 0 || updatedAt > timestamp || updatedAt < timestamp - tokenPricingTimeout) {
            revert InvalidDataReturned();
        }
        uint256 decimals = redstoneOracle.decimals;
        // Redstone feeds have certain decimal precisions, does not neccessarily conform to underlying asset.
        uint256 normalizedPrice = decimals == 18 ? priceUint : priceUint * 10 ** (18 - decimals);

        return _denominationPricing(redstoneOracle.denomination, normalizedPrice, token);
    }
    // slither-disable-end timestamp

    /// @dev internal getter to access `tokenToRedstoneOracle` mapping, enforces address(0) check.
    function _getRedstoneInfo(address token) internal view returns (RedstoneInfo memory redstoneInfo) {
        redstoneInfo = redstoneOracleInfo[token];
        Errors.verifyNotZero(address(redstoneInfo.oracle), "redStoneOracle");
    }
}
