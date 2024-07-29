// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISummaryStatsHook } from "src/interfaces/strategy/ISummaryStatsHook.sol";
import { IAutopoolStrategy } from "src/interfaces/strategy/IAutopoolStrategy.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";

/// @title Allow the configuration of APR boosts to represent future "points" earnings
contract PointsHook is ISummaryStatsHook, SystemComponent, SecurityBase {
    /// =====================================================
    /// Constant Vars
    /// =====================================================

    /// @notice Maximum allowed boost
    uint256 public constant MAX_BOOST = 0.1e18;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Returns the configured boost for the given DestinationVault address
    mapping(address => uint256) public destinationBoosts;

    /// =====================================================
    /// Events
    /// =====================================================

    event BoostsSet(address[] destinationVaults, uint256[] boosts);

    /// =====================================================
    /// Errors
    /// =====================================================

    error BoostExceedsMax(uint256 providedValue);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Configure boosts for the give DestinationVaults
    /// @param destinationVaults List of DestinationVaults to configure
    /// @param boosts List of boosts to configure for the DestinationVaults
    function setBoosts(
        address[] memory destinationVaults,
        uint256[] memory boosts
    ) external hasRole(Roles.STATS_HOOK_POINTS_ADMIN) {
        uint256 boostsLen = boosts.length;
        Errors.verifyNotZero(boostsLen, "boostsLen");
        Errors.verifyArrayLengths(destinationVaults.length, boostsLen, "boosts");

        IDestinationVaultRegistry dvRegistry = systemRegistry.destinationVaultRegistry();

        for (uint256 i = 0; i < boostsLen;) {
            address destinationVault = destinationVaults[i];
            uint256 boost = boosts[i];

            dvRegistry.verifyIsRegistered(destinationVault);

            if (boost > MAX_BOOST) {
                revert BoostExceedsMax(boost);
            }

            destinationBoosts[destinationVault] = boost;

            unchecked {
                ++i;
            }
        }

        emit BoostsSet(destinationVaults, boosts);
    }

    /// @inheritdoc ISummaryStatsHook
    function execute(
        IStrategy.SummaryStats memory stats,
        IAutopool,
        address destAddress,
        uint256,
        IAutopoolStrategy.RebalanceDirection,
        uint256
    ) external view returns (IStrategy.SummaryStats memory) {
        stats.baseApr += destinationBoosts[destAddress];

        return stats;
    }
}
