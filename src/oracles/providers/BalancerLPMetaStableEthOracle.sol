// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IProtocolFeesCollector } from "src/interfaces/external/balancer/IProtocolFeesCollector.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { IRateProvider } from "src/interfaces/external/balancer/IRateProvider.sol";
import { SystemComponent } from "src/SystemComponent.sol";

/// @title Price oracle for Balancer Meta Stable pools
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract BalancerLPMetaStableEthOracle is SystemComponent, IPriceOracle {
    /// @notice Balancer vault all BPTs registered to point here should reference
    /// @dev BPTs themselves are configured with an immutable vault reference
    IBalancerVault public immutable balancerVault;

    error InvalidTokenCount(address token, uint256 length);
    error InvalidPool(address token);

    constructor(ISystemRegistry _systemRegistry, IBalancerVault _balancerVault) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_balancerVault), "_balancerVault");

        balancerVault = _balancerVault;
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");

        // Checks to make sure pool being priced is not ComposableStablePool.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = token.call(abi.encodeWithSignature("getActualSupply()"));
        if (success) revert InvalidPool(token);

        BalancerUtilities.checkReentrancy(address(balancerVault));

        IBalancerMetaStablePool pool = IBalancerMetaStablePool(token);
        bytes32 poolId = pool.getPoolId();

        // Will revert with BAL#500 on invalid pool id
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);

        // Meta stable vaults only support two tokens, but the vault will resolve any thing
        // Try to verify we're using the right oracle here
        if (tokens.length != 2) {
            revert InvalidTokenCount(token, tokens.length);
        }

        // Use the min price of the tokens
        uint256 px0 = systemRegistry.rootPriceOracle().getPriceInEth(address(tokens[0]));
        uint256 px1 = systemRegistry.rootPriceOracle().getPriceInEth(address(tokens[1]));

        // slither-disable-start divide-before-multiply
        IRateProvider[] memory rateProviders = pool.getRateProviders();
        px0 = px0 * 1e18 / (address(rateProviders[0]) != address(0) ? rateProviders[0].getRate() : 1e18);
        px1 = px1 * 1e18 / (address(rateProviders[1]) != address(0) ? rateProviders[1].getRate() : 1e18);
        // slither-disable-end divide-before-multiply

        // Calculate the virtual price of the pool removing accrued admin fees
        // that haven't been taken yet by Balancer
        // slither-disable-start divide-before-multiply
        uint256 virtualPrice = pool.getRate(); // e18
        uint256 totalSupply = pool.totalSupply(); // e18
        uint256 unscaledInv = (virtualPrice * totalSupply) / 1e18; // e18
        uint256 lastInvariant = pool.getLastInvariant(); // e18
        if (unscaledInv > lastInvariant) {
            uint256 delta = unscaledInv - lastInvariant; // e18 - e18 -> e18
            uint256 swapFee = balancerVault.getProtocolFeesCollector().getSwapFeePercentage(); //e18
            uint256 protocolPortion = ((delta * swapFee) / 1e18); // e18
            uint256 scaledInv = unscaledInv - protocolPortion; // e18 - e18 -> e18
            virtualPrice = scaledInv * 1e18 / totalSupply; // e36 / e18 -> e18
        }

        price = ((px0 > px1 ? px1 : px0) * virtualPrice) / 1e18;
        // slither-disable-end divide-before-multiply
    }
}
