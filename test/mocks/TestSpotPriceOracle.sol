// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { SystemComponent } from "src/SystemComponent.sol";

/**
 * @notice This contract is a streamlined implementation of ISpotPriceOracle.
 *  It's designed for tests that are agnostic to the type of price oracle being used.
 */
contract TestSpotPriceOracle is SystemComponent, ISpotPriceOracle {
    mapping(bytes32 => uint256) public spotPrices;
    mapping(bytes32 => address) public actualQuoteTokens;
    mapping(bytes32 => uint256) public lpSupply;
    mapping(bytes32 => ISpotPriceOracle.ReserveItemInfo[]) public reserveInfos;

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /**
     * @dev Use this function to manually set the spot price
     * @param token The token address to set the spot price for
     * @param pool The pool address to set the spot price for
     * @param requestedQuoteToken The requested quote token for the spot price
     * @param price The spot price to set
     * @param actualQuoteToken The actual quote token to set
     */
    function setSpotPriceAndQuoteToken(
        address token,
        address pool,
        address requestedQuoteToken,
        uint256 price,
        address actualQuoteToken
    ) external {
        bytes32 key = keccak256(abi.encodePacked(token, pool, requestedQuoteToken));
        spotPrices[key] = price;
        actualQuoteTokens[key] = actualQuoteToken;
    }

    /**
     * @dev Use this function to manually set the total LP supply and reserve info.
     *  To avoid the "Copying of type struct memory to storage not yet supported" error we loop through the reserves and
     * set them one by one.
     * @param pool The pool address to set the LP supply and reserve info for
     * @param lpToken The LP token to set the LP supply and reserve info for
     * @param quoteToken The quote token for the LP supply and reserve info
     * @param totalSupply The total LP supply to set
     * @param reserves The reserve info to set
     */
    function setSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken,
        uint256 totalSupply,
        ISpotPriceOracle.ReserveItemInfo[] memory reserves
    ) external {
        bytes32 key = keccak256(abi.encodePacked(pool, lpToken, quoteToken));
        lpSupply[key] = totalSupply;

        for (uint256 i = 0; i < reserves.length; i++) {
            reserveInfos[key].push(reserves[i]);
        }
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) external view returns (uint256 price, address actualQuoteToken) {
        bytes32 key = keccak256(abi.encodePacked(token, pool, requestedQuoteToken));
        price = spotPrices[key];
        actualQuoteToken = actualQuoteTokens[key];
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken
    ) external view returns (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) {
        bytes32 key = keccak256(abi.encodePacked(pool, lpToken, quoteToken));
        totalLPSupply = lpSupply[key];
        reserves = reserveInfos[key];
    }
}
