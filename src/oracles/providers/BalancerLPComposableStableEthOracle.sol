// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IAsset } from "src/interfaces/external/balancer/IAsset.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { SystemComponent } from "src/SystemComponent.sol";

/// @title Price oracle for Balancer Composable Stable pools
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract BalancerLPComposableStableEthOracle is SystemComponent, IPriceOracle, ISpotPriceOracle {
    /// @notice The Balancer Vault that all tokens we're resolving here should reference
    /// @dev BPTs themselves are configured with an immutable vault reference
    IVault public immutable balancerVault;

    error InvalidPrice(address token, uint256 price);
    error InvalidToken(address token);

    constructor(ISystemRegistry _systemRegistry, IVault _balancerVault) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_balancerVault), "_balancerVault");

        balancerVault = _balancerVault;
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");

        BalancerUtilities.checkReentrancy(address(balancerVault));

        IBalancerComposableStablePool pool = IBalancerComposableStablePool(token);
        bytes32 poolId = pool.getPoolId();

        // Will revert with BAL#500 on invalid pool id
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);

        uint256 bptIndex = pool.getBptIndex();
        uint256 minPrice = type(uint256).max;
        uint256 nTokens = tokens.length;

        for (uint256 i = 0; i < nTokens;) {
            if (i != bptIndex) {
                // Our prices are always in 1e18
                uint256 tokenPrice = systemRegistry.rootPriceOracle().getPriceInEth(address(tokens[i]));
                tokenPrice = tokenPrice * 1e18 / pool.getTokenRate(tokens[i]);
                if (tokenPrice < minPrice) {
                    minPrice = tokenPrice;
                }
            }

            unchecked {
                ++i;
            }
        }

        // If it's still the default vault we set, something went wrong
        if (minPrice == type(uint256).max) {
            revert InvalidPrice(token, type(uint256).max);
        }

        // Intentional precision loss, prices should always be in e18
        // slither-disable-next-line divide-before-multiply
        price = (minPrice * pool.getRate()) / 1e18;
    }

    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) public returns (uint256 price, address actualQuoteToken) {
        uint256 amountIn = 1e18;
        bytes32 poolId = IBalancerComposableStablePool(pool).getPoolId();

        IVault.BatchSwapStep[] memory steps = new IVault.BatchSwapStep[](1);
        steps[0] = IVault.BatchSwapStep(poolId, 0, 1, amountIn, "");

        // Will revert with BAL#500 on invalid pool id
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);

        uint256 nTokens = tokens.length;
        int256 tokenIndex = -1;
        int256 quoteTokenIndex = -1;

        // Find the token and quote token indices
        for (uint256 i = 0; i < nTokens; ++i) {
            address t = address(tokens[i]);

            if (t == token) {
                tokenIndex = int256(i);
            } else if (t == requestedQuoteToken) {
                quoteTokenIndex = int256(i);
            }

            // Break out of the loop if both indices are found.
            if (tokenIndex != -1 && quoteTokenIndex != -1) {
                break;
            }
        }

        if (tokenIndex == -1) revert InvalidToken(token);

        // Selects an alternative quote token if the requested one is not found in the pool.
        // It chooses the first available token that is neither the input token (token) nor the pool address itself.
        // This is important as pools may include their address as a token, which should not be chosen as a quote token.
        if (quoteTokenIndex == -1) {
            for (uint256 i = 0; i < nTokens; ++i) {
                address t = address(tokens[i]);

                if (t != token && t != pool) {
                    quoteTokenIndex = int256(i);
                    break;
                }
            }
        }

        // Revert if no valid quote token is found.
        if (quoteTokenIndex == -1) revert InvalidToken(requestedQuoteToken);

        // Set the actual quote token based on the found index.
        actualQuoteToken = address(tokens[uint256(quoteTokenIndex)]);

        // Prepare swap parameters.
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokens[uint256(tokenIndex)]));
        assets[1] = IAsset(actualQuoteToken);

        IVault.FundManagement memory funds = IVault.FundManagement(address(this), false, payable(address(this)), false);

        // Perform the batch swap query to get price information.
        int256[] memory assetDeltas = balancerVault.queryBatchSwap(IVault.SwapKind.GIVEN_IN, steps, assets, funds);

        // Calculate the price using the returned asset delta.
        price = (uint256(-assetDeltas[1]) * 1e18) / amountIn;
    }
}
