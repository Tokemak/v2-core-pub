// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

interface ICurveResolver {
    /// @notice Resolve details of a Curve pool regardless of type or version
    /// @dev This resolves tokens without unwrapping to underlying in the case of meta pools.
    /// If you need a dynamic array of tokens use Arrays.convertFixedCurveTokenArrayToDynamic(tokens,numTokens)
    /// @param poolAddress pool address to lookup
    /// @return tokens tokens that make up the pool
    /// @return numTokens the number of tokens. tokens are not unwrapped.
    /// @return isStableSwap is this a StableSwap pool. false = CryptoSwap
    function resolve(address poolAddress)
        external
        view
        returns (address[8] memory tokens, uint256 numTokens, bool isStableSwap);

    /// @notice Resolve details of a Curve pool regardless of type or version
    /// @dev This resolves tokens without unwrapping to underlying in the case of meta pools.
    /// If you need a dynamic array of tokens use Arrays.convertFixedCurveTokenArrayToDynamic(tokens,numTokens)
    /// @param poolAddress pool address to lookup
    /// @return tokens tokens that make up the pool
    /// @return numTokens the number of tokens. tokens are not unwrapped
    /// @return lpToken lp token of the pool
    /// @return isStableSwap is this a StableSwap pool. false = CryptoSwap
    function resolveWithLpToken(address poolAddress)
        external
        view
        returns (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap);

    /// @notice Get the lp token of a Curve pool
    /// @param poolAddress pool address to lookup
    function getLpToken(address poolAddress) external view returns (address);

    function getReservesInfo(address poolAddress) external view returns (uint256[8] memory balances);
}
