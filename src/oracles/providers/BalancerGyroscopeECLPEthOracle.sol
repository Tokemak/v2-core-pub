// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import {
    BalancerBaseOracle,
    ISpotPriceOracle,
    Errors,
    IERC20Metadata
} from "src/oracles/providers/base/BalancerBaseOracle.sol";
import { IBalancerGyroPool } from "src/interfaces/external/balancer/IBalancerGyroPool.sol";

/// @title Price oracle for Gyroscope pools with Balancer interface
contract BalancerGyroscopeECLPEthOracle is BalancerBaseOracle {
    uint256 public constant POOL_TOKENS_CONSTANT = 2;

    constructor(
        ISystemRegistry _systemRegistry,
        IVault _balancerVault
    ) BalancerBaseOracle(_systemRegistry, _balancerVault) { }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "balGyro";
    }

    function getTotalSupply_(address lpToken) internal virtual override returns (uint256 totalSupply) {
        totalSupply = IBalancerGyroPool(lpToken).getActualSupply();
    }

    function getPoolTokens_(address pool)
        internal
        virtual
        override
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        (tokens, balances) = BalancerUtilities._getPoolTokens(balancerVault, pool);
    }

    function _getSpotPrice(
        address token,
        address pool,
        IERC20[] memory tokens,
        address
    ) internal view override returns (uint256 price, address actualQuoteToken) {
        Errors.verifyArrayLengths(tokens.length, POOL_TOKENS_CONSTANT, "tokens");

        int256 tokenIdx = -1;
        if (token == address(tokens[0])) {
            tokenIdx = 0;
        } else if (token == address(tokens[1])) {
            tokenIdx = 1;
        }

        if (tokenIdx == -1) revert InvalidToken(token);

        // Gyro pools return token0 in terms of token1
        price = IBalancerGyroPool(pool).getPrice();

        // Adjust price in case that token desired to be priced is idx 1.  Set actualQuote for return
        if (tokenIdx == 1) {
            // Price in e18
            price = 1e36 / price;
            actualQuoteToken = address(tokens[0]);
        } else {
            actualQuoteToken = address(tokens[1]);
        }

        // Spot in e18 right now, if quote token not e18 adjust by decimals
        uint256 quoteTokenDecimals = IERC20Metadata(actualQuoteToken).decimals();
        if (quoteTokenDecimals < 18) {
            price = price / 10 ** (18 - quoteTokenDecimals);
        }
    }
}
