// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @dev Used for curve contracts that are meant to be initialized by a factory being initialized manually.
interface IStableSwapInitializable {
    function initialize(
        string memory name, // Must be less than 32 characters, reverts.
        string memory symbol, // Must be less than 10 characters, reverts.
        address[4] memory coins,
        uint256[4] memory rateMultipliers,
        uint256 a,
        uint256 fee
    ) external;
}
