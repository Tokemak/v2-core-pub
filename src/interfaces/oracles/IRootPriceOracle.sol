// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

/// @notice Retrieve a price for any token used in the system
interface IRootPriceOracle {
    /// @notice Returns a fair price for the provided token in ETH
    /// @param token token to get the price of
    /// @return price the price of the token in ETH
    function getPriceInEth(address token) external returns (uint256 price);

    /// @notice Returns a spot price for the provided token in ETH, utilizing specified liquidity pool
    /// @param token token to get the spot price of
    /// @param pool liquidity pool to be used for price determination
    /// @return price the spot price of the token in ETH based on the provided pool
    function getSpotPriceInEth(address token, address pool) external returns (uint256);
}
