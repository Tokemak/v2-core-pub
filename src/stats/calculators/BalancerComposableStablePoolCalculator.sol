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

        uint256 nTokens = allTokens.length;
        tokens = new IERC20[](nTokens - 1);
        balances = new uint256[](nTokens - 1);

        uint256 lastIndex = 0;
        uint256 bptIndex = IBalancerComposableStablePool(poolAddress).getBptIndex();
        for (uint256 i = 0; i < nTokens;) {
            // skip pool token
            if (i == bptIndex) {
                unchecked {
                    ++i;
                }
                continue;
            }
            // copy tokens and balances
            tokens[lastIndex] = allTokens[i];
            balances[lastIndex] = allBalances[i];
            unchecked {
                ++i;
                ++lastIndex;
            }
        }
    }
}
