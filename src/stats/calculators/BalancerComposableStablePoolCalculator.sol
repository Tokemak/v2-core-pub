// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";

contract BalancerComposableStablePoolCalculator is BalancerStablePoolCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry,
        address _balancerVault
    ) BalancerStablePoolCalculatorBase(_systemRegistry, _balancerVault) { }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        virtualPrice = IBalancerComposableStablePool(poolAddress).getRate();
    }

    function getPoolTokens() internal view override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (IERC20[] memory allTokens, uint256[] memory allBalances) =
            BalancerUtilities._getPoolTokens(balancerVault, poolAddress);

        uint256 numTokens = allTokens.length;
        if (numTokens != allBalances.length) {
            revert InvalidPool(poolAddress);
        }

        tokens = new IERC20[](numTokens - 1);
        balances = new uint256[](numTokens - 1);

        uint256 lastIndex = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            if (lastIndex == numTokens - 1) {
                // reached the end of the array and no pool token found
                return (allTokens, allBalances);
            }
            // copy tokens and balances skipping the pool token
            if (address(allTokens[i]) != poolAddress) {
                tokens[lastIndex] = allTokens[i];
                balances[lastIndex] = allBalances[i];
                lastIndex++;
            }
        }
    }
}
