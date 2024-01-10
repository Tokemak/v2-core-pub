// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/utils/Errors.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract RootPriceOracle is SystemComponent, SecurityBase, IRootPriceOracle {
    mapping(address => IPriceOracle) public tokenMappings;
    mapping(address => ISpotPriceOracle) public poolMappings;

    event TokenRemoved(address token);
    event TokenRegistered(address token, address oracle);
    event TokenRegistrationReplaced(address token, address oldOracle, address newOracle);

    // pool-handler specific events
    event PoolRegistered(address indexed pool, address indexed oracle);
    event PoolRegistrationReplaced(address indexed pool, address indexed oldOracle, address indexed newOracle);
    event PoolRemoved(address indexed pool);

    error AlreadyRegistered(address token);
    error MissingTokenOracle(address token);
    error MappingDoesNotExist(address token);
    error ReplaceOldMismatch(address token, address oldExpected, address oldActual);
    error ReplaceAlreadyMatches(address token, address newOracle);

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// @notice Register a new token to oracle mapping
    /// @dev May require additional registration in the oracle itself
    /// @param token address of the token to register
    /// @param oracle address of the oracle to use to lookup price
    function registerMapping(address token, IPriceOracle oracle) external onlyOwner {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(address(oracle), "oracle");
        Errors.verifySystemsMatch(address(this), address(oracle));

        // We want the operation of replacing a mapping to be an explicit
        // call so we don't accidentally overwrite something
        if (address(tokenMappings[token]) != address(0)) {
            revert AlreadyRegistered(token);
        }

        tokenMappings[token] = oracle;

        emit TokenRegistered(token, address(oracle));
    }

    /// @notice Replace an existing token -> oracle mapping
    /// @dev Must exist, matching existing, and new != old value to successfully replace
    /// @param token address of the token to register
    /// @param oldOracle existing oracle address
    /// @param newOracle new oracle address
    function replaceMapping(address token, IPriceOracle oldOracle, IPriceOracle newOracle) external onlyOwner {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(address(oldOracle), "oldOracle");
        Errors.verifyNotZero(address(newOracle), "newOracle");
        Errors.verifySystemsMatch(address(this), address(newOracle));

        // We want to ensure you know what you're replacing so ensure
        // you provide a matching old value
        if (tokenMappings[token] != oldOracle) {
            revert ReplaceOldMismatch(token, address(oldOracle), address(tokenMappings[token]));
        }

        // If the old and new values match we can assume you're not doing
        // what you think you're doing so we just fail
        if (oldOracle == newOracle) {
            revert ReplaceAlreadyMatches(token, address(newOracle));
        }

        tokenMappings[token] = newOracle;

        emit TokenRegistrationReplaced(token, address(oldOracle), address(newOracle));
    }

    /// @notice Remove a token to oracle mapping
    /// @dev Must exist. Does not remove any additional configuration from the oracle itself
    /// @param token address of the token that is registered
    function removeMapping(address token) external onlyOwner {
        Errors.verifyNotZero(token, "token");

        // If you're trying to remove something that doesn't exist then
        // some condition you're expecting isn't true. We revert so you can reevaluate
        if (address(tokenMappings[token]) == address(0)) {
            revert MappingDoesNotExist(token);
        }

        delete tokenMappings[token];

        emit TokenRemoved(token);
    }

    /// @notice Register a new liquidity pool to its LP oracle
    /// @dev May require additional registration in the oracle itself
    /// @param pool address of the liquidity pool
    /// @param oracle address of the LP oracle
    function registerPoolMapping(address pool, ISpotPriceOracle oracle) external onlyOwner {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(address(oracle), "oracle");
        Errors.verifySystemsMatch(address(this), address(oracle));

        if (address(poolMappings[pool]) != address(0)) {
            revert AlreadyRegistered(pool);
        }

        poolMappings[pool] = oracle;

        emit PoolRegistered(pool, address(oracle));
    }

    /// @notice Replace an existing oracle for a specified liquidity pool
    /// @dev Must exist, matching existing, and new != old value to successfully replace
    /// @param pool address of the liquidity pool
    /// @param oldOracle address of the current LP oracle
    /// @param newOracle address of the new LP oracle
    function replacePoolMapping(
        address pool,
        ISpotPriceOracle oldOracle,
        ISpotPriceOracle newOracle
    ) external onlyOwner {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(address(oldOracle), "oldOracle");
        Errors.verifyNotZero(address(newOracle), "newOracle");
        Errors.verifySystemsMatch(address(this), address(newOracle));

        ISpotPriceOracle currentOracle = poolMappings[pool];

        if (currentOracle != oldOracle) revert ReplaceOldMismatch(pool, address(oldOracle), address(currentOracle));
        if (oldOracle == newOracle) revert ReplaceAlreadyMatches(pool, address(newOracle));

        poolMappings[pool] = newOracle;

        emit PoolRegistrationReplaced(pool, address(oldOracle), address(newOracle));
    }

    /// @notice Remove an existing oracle for a specified liquidity pool
    /// @dev Must exist. Does not remove any additional configuration from the oracle itself
    /// @param pool address of the liquidity pool that needs oracle removal
    function removePoolMapping(address pool) external onlyOwner {
        Errors.verifyNotZero(pool, "pool");

        if (address(poolMappings[pool]) == address(0)) revert MappingDoesNotExist(pool);

        delete poolMappings[pool];

        emit PoolRemoved(pool);
    }

    /// @dev This and all price oracles are not view fn's so that we can perform the Curve reentrancy check
    /// @inheritdoc IRootPriceOracle
    function getPriceInEth(address token) external returns (uint256 price) {
        // Skip the token address(0) check and just rely on the oracle lookup
        // Emit token so we can figure out what was actually 0 later
        IPriceOracle oracle = tokenMappings[token];
        if (address(oracle) == address(0)) revert MissingTokenOracle(token);

        price = oracle.getPriceInEth(token);
    }

    /// @inheritdoc IRootPriceOracle
    function getSpotPriceInEth(address token, address pool) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(pool, "pool");

        ISpotPriceOracle oracle = poolMappings[pool];
        if (address(oracle) == address(0)) revert MissingTokenOracle(pool);

        address weth = address(systemRegistry.weth());

        // Retrieve the spot price with weth as the requested quote token
        (uint256 rawPrice, address actualQuoteToken) = oracle.getSpotPrice(token, pool, weth);

        // If the returned quote token is weth, return the price directly
        if (actualQuoteToken == weth) return rawPrice;

        // If not, get the conversion rate from the actualQuoteToken to weth and then derive the spot price
        IPriceOracle tokenOracle = tokenMappings[actualQuoteToken];
        if (address(tokenOracle) == address(0)) revert MissingTokenOracle(actualQuoteToken);

        uint256 conversionRate = tokenOracle.getPriceInEth(actualQuoteToken);

        uint256 decimals = IERC20Metadata(actualQuoteToken).decimals();

        price = rawPrice * conversionRate / (10 ** decimals);

        return price;
    }

    function getPriceInQuote(address base, address quote) external returns (uint256) {
        IPriceOracle baseOracle = tokenMappings[base];
        IPriceOracle quoteOracle = tokenMappings[quote];

        if (address(baseOracle) == address(0) || address(quoteOracle) == address(0)) {
            // Revert token being priced.
            revert MissingTokenOracle(base);
        }

        uint256 basePriceInEth = baseOracle.getPriceInEth(base);
        uint256 quotePriceInEth = quoteOracle.getPriceInEth(quote);

        return (basePriceInEth * (10 ** 18)) / quotePriceInEth;
    }
}
