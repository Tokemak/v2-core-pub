// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

contract CurveResolverMainnet is ICurveResolver {
    ICurveMetaRegistry public immutable curveMetaRegistry;

    constructor(ICurveMetaRegistry _curveMetaRegistry) {
        Errors.verifyNotZero(address(_curveMetaRegistry), "_curveMetaRegistry");

        curveMetaRegistry = _curveMetaRegistry;
    }

    /// @inheritdoc ICurveResolver
    function resolve(address poolAddress)
        public
        view
        returns (address[8] memory tokens, uint256 numTokens, bool isStableSwap)
    {
        Errors.verifyNotZero(poolAddress, "poolAddress");

        tokens = curveMetaRegistry.get_coins(poolAddress);
        numTokens = curveMetaRegistry.get_n_coins(poolAddress);

        // Using the presence of a gamma() fn as an indicator of pool type
        // Zero check for the poolAddress is above
        // slither-disable-start low-level-calls,missing-zero-check,unchecked-lowlevel
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = poolAddress.staticcall(abi.encodeWithSignature("gamma()"));
        // slither-disable-end low-level-calls,missing-zero-check,unchecked-lowlevel

        isStableSwap = !success;
    }

    /// @inheritdoc ICurveResolver
    function resolveWithLpToken(address poolAddress)
        external
        view
        returns (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap)
    {
        (tokens, numTokens, isStableSwap) = resolve(poolAddress);

        lpToken = curveMetaRegistry.get_lp_token(poolAddress);
    }

    /// @inheritdoc ICurveResolver
    function getLpToken(address poolAddress) external view returns (address) {
        return curveMetaRegistry.get_lp_token(poolAddress);
    }

    /// @inheritdoc ICurveResolver
    function getReservesInfo(address poolAddress) external view returns (uint256[8] memory balances) {
        Errors.verifyNotZero(poolAddress, "poolAddress");
        balances = curveMetaRegistry.get_balances(poolAddress);
    }
}
