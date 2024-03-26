// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerBaseOracle } from "src/oracles/providers/base/BalancerBaseOracle.sol";

/// @title Price oracle for Balancer Composable Stable pools
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract BalancerLPComposableStableEthOracle is BalancerBaseOracle {
    constructor(
        ISystemRegistry _systemRegistry,
        IVault _balancerVault
    ) BalancerBaseOracle(_systemRegistry, _balancerVault) { }

    function getTotalSupply_(address lpToken) internal virtual override returns (uint256 totalSupply) {
        totalSupply = IBalancerComposableStablePool(lpToken).getActualSupply();
    }

    function getPoolTokens_(address pool)
        internal
        virtual
        override
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        (tokens, balances) = BalancerUtilities._getComposablePoolTokensSkipBpt(balancerVault, pool);
    }
}
