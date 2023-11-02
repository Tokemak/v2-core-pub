// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

/// @notice An oracle that can provide spot prices for tokens using specific liquidity pools
interface ISpotPriceOracle {
    /**
     * @notice Retrieve the spot price for a token in a specified quote currency utilizing a specific liquidity pool
     * @dev The function will attempt to retrieve the price in the requested quote currency,
     *      but might return a price in an alternative quote currency if the requested one isn't available.
     *      It's the caller's responsibility to handle the potentially different returned quote currency.
     * @param token The token to get the spot price of
     * @param pool The liquidity pool to use for the price retrieval
     * @param requestedQuoteToken The desired quote token (e.g. WETH) for the returned price
     * @return price The spot price of the token
     * @return actualQuoteToken The actual quote token used for the returned price
     */
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) external returns (uint256 price, address actualQuoteToken);
}
