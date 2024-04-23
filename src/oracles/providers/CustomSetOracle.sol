// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";

/**
 * @notice Fall back oracle that we can set manually through a secured call
 * @dev We are ignoring checks for timestamps greater than u32. Hopefully we'll be kicking ourselves
 * for this move in 83 years.
 */
contract CustomSetOracle is SystemComponent, SecurityBase, IPriceOracle {
    struct Price {
        uint192 price;
        uint32 maxAge;
        uint32 timestamp;
    }

    /// @notice Maximum age a price can be from when it was originally queried
    /// @dev Will revert on getPriceInEth if older
    uint256 public maxAge;

    /// @notice All current prices for registered tokens
    /// @dev If maxAge is 0 then the token isn't registered
    mapping(address => Price) public prices;

    event TokensRegistered(address[] tokens, uint256[] maxAges);
    event PricesSet(address[] tokens, uint256[] ethPrices, uint256[] queriedTimestamps);
    event MaxAgeSet(uint256 maxAge);
    event TokensUnregistered(address[] tokens);

    error InvalidAge(uint256 age);
    error InvalidPrice(address token, uint256 price);
    error InvalidTimestamp(address token, uint256 timestamp);
    error InvalidToken(address token);
    error AlreadyRegistered(address token);
    error TokenNotRegistered(address token);
    error TimestampOlderThanCurrent(address token, uint256 current, uint256 newest);
    error StalePriceDataError(uint256 timestamp, uint256 maxAge, uint256 current);

    constructor(
        ISystemRegistry _systemRegistry,
        uint256 _maxAge
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        _setMaxAge(_maxAge);
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "customSet";
    }

    /// @notice Change the max allowable per-token age
    /// @param age New allowed age
    function setMaxAge(uint256 age) external hasRole(Roles.ORACLE_MANAGER_ROLE) {
        _setMaxAge(age);
    }

    /// @notice Register tokens that should be resolvable through this oracle
    /// @param tokens addresses of tokens to register
    /// @param maxAges the max allowed age of a tokens price before it will revert on retrieval
    function registerTokens(
        address[] memory tokens,
        uint256[] memory maxAges
    ) external hasRole(Roles.ORACLE_MANAGER_ROLE) {
        _registerTokens(tokens, maxAges, false);
    }

    /// @notice Update the max age of tokens that are already registered
    /// @param tokens addresses of tokens to update
    /// @param maxAges the max allowed age of a tokens price before it will revert on retrieval
    function updateTokenMaxAges(
        address[] memory tokens,
        uint256[] memory maxAges
    ) external hasRole(Roles.ORACLE_MANAGER_ROLE) {
        _registerTokens(tokens, maxAges, true);
    }

    /// @notice Unregister tokens that have been previously configured
    /// @param tokens addresses of the tokens to unregister
    function unregisterTokens(address[] memory tokens) external hasRole(Roles.ORACLE_MANAGER_ROLE) {
        uint256 len = tokens.length;
        Errors.verifyNotZero(len, "len");

        // slither-disable-start costly-loop
        for (uint256 i = 0; i < len; ++i) {
            address token = tokens[i];
            Errors.verifyNotZero(token, "token");

            if (prices[token].maxAge == 0) {
                revert InvalidToken(token);
            }

            delete prices[token];
        }
        // slither-disable-end costly-loop

        emit TokensUnregistered(tokens);
    }

    /// @notice Update the price of one or more registered tokens
    /// @dev Only callable by the CUSTOM_ORACLE_EXECUTOR
    /// @param tokens address of the tokens price we are setting
    /// @param ethPrices prices of the tokens we're setting
    /// @param queriedTimestamps the timestamps of when each price was queried
    function setPrices(
        address[] memory tokens,
        uint256[] memory ethPrices,
        uint256[] memory queriedTimestamps
    ) external hasRole(Roles.CUSTOM_ORACLE_EXECUTOR) {
        uint256 len = tokens.length;
        Errors.verifyNotZero(len, "len");
        Errors.verifyArrayLengths(len, ethPrices.length, "token+prices");
        Errors.verifyArrayLengths(len, queriedTimestamps.length, "token+timestamps");

        for (uint256 i = 0; i < len; ++i) {
            address token = tokens[i];
            uint256 price = ethPrices[i];
            uint256 timestamp = queriedTimestamps[i];

            // Ensure the price will fit where we want it
            if (price > type(uint192).max) {
                revert InvalidPrice(token, price);
            }

            // Can't set a timestamp in the future
            // Covers our type casting check as well
            // slither-disable-next-line timestamp
            if (timestamp > block.timestamp) {
                revert InvalidTimestamp(token, timestamp);
            }

            Price memory data = prices[token];

            // MaxAge == 0 is our check for registered tokens. 0 isn't allowed
            if (data.maxAge == 0) {
                revert TokenNotRegistered(token);
            }

            // Can't set a price queried from a timestamp that is earlier that the
            // one we have currently
            if (timestamp < data.timestamp) {
                revert TimestampOlderThanCurrent(token, data.timestamp, timestamp);
            }

            // Can't set a price if its queriedTimestamp + maxAge is before the current block
            // Check to prevent writing stale prices if a tx is delayed in the mempool.
            if (timestamp + data.maxAge < block.timestamp) {
                revert StalePriceDataError(timestamp, data.maxAge, block.timestamp);
            }

            // Save the data
            data.price = uint192(price);
            data.timestamp = uint32(timestamp);
            prices[token] = data;
        }

        emit PricesSet(tokens, ethPrices, queriedTimestamps);
    }

    /// @notice Returns true for a token that is registered with this oracle
    /// @param token address to check
    function isRegistered(address token) external view returns (bool) {
        return prices[token].maxAge > 0;
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external view returns (uint256 price) {
        Price memory data = prices[token];

        // MaxAge == 0 is our check for registered tokens. 0 isn't allowed
        if (data.maxAge == 0) {
            revert TokenNotRegistered(token);
        }

        // Ensure the data isn't too stale to use
        // slither-disable-next-line timestamp
        if (data.timestamp + data.maxAge < block.timestamp) {
            revert InvalidAge(block.timestamp - data.timestamp);
        }

        price = data.price;
    }

    function _setMaxAge(uint256 _maxAge) private {
        Errors.verifyNotZero(_maxAge, "maxAge");
        if (_maxAge > type(uint32).max) {
            revert InvalidAge(_maxAge);
        }
        maxAge = _maxAge;

        emit MaxAgeSet(_maxAge);
    }

    /// @notice Register tokens that should be resolvable through this oracle
    /// @param tokens addresses of tokens to register
    /// @param maxAges the max allowed age of a tokens price before it will revert on retrieval
    /// @param allowUpdate whether to allow a change to an already registered token
    function _registerTokens(address[] memory tokens, uint256[] memory maxAges, bool allowUpdate) private {
        uint256 len = tokens.length;
        Errors.verifyNotZero(len, "len");
        Errors.verifyArrayLengths(len, maxAges.length, "token+ages");

        // Process incoming tokens ensure that the token isn't 0
        // That the age isn't over the max
        // We can update the configured age through this function
        for (uint256 i = 0; i < len; ++i) {
            address token = tokens[i];
            Errors.verifyNotZero(token, "token");

            uint256 currentAge = prices[token].maxAge;
            if (!allowUpdate && currentAge > 0) {
                revert AlreadyRegistered(token);
            }
            if (allowUpdate && currentAge == 0) {
                revert TokenNotRegistered(token);
            }

            uint256 maxTokenAge = maxAges[i];
            Errors.verifyNotZero(maxTokenAge, "maxAge");
            if (maxTokenAge > maxAge) {
                revert InvalidAge(maxTokenAge);
            }

            prices[token].maxAge = uint32(maxTokenAge);
        }

        emit TokensRegistered(tokens, maxAges);
    }
}
