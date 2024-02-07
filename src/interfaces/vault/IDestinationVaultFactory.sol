// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

/// @notice Creates and registers Destination Vaults for the system
interface IDestinationVaultFactory is ISystemComponent {
    /// @notice Creates a vault of the specified type
    /// @dev vaultType will be bytes32 encoded and checked that a template is registered
    /// @param vaultType human readable key of the vault template
    /// @param baseAsset Base asset of the system. WETH/USDC/etc
    /// @param underlyer Underlying asset the vault will wrap
    /// @param incentiveCalculator Incentive calculator of the vault
    /// @param additionalTrackedTokens Any tokens in addition to base and underlyer that should be tracked
    /// @param salt Contracts are created via CREATE2 with this value
    /// @param params params to be passed to vaults initialize function
    /// @return vault address of the newly created destination vault
    function create(
        string memory vaultType,
        address baseAsset,
        address underlyer,
        address incentiveCalculator,
        address[] memory additionalTrackedTokens,
        bytes32 salt,
        bytes memory params
    ) external returns (address vault);
}
