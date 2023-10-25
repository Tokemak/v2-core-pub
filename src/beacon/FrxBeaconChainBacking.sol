// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBeaconChainBacking } from "src/interfaces/beacon/IBeaconChainBacking.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

contract FrxBeaconChainBacking is SystemComponent, SecurityBase, IBeaconChainBacking {
    address public immutable token;
    uint96 public immutable decimalPad;

    Ratio public currentRatio;

    struct Ratio {
        uint208 ratio;
        uint48 timestamp;
    }

    event RatioUpdated(uint208 ratio, uint208 totalAssets, uint208 totalLiabilities, uint48 timestamp);

    constructor(
        ISystemRegistry _systemRegistry,
        address _token
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(_token, "_token");
        // slither-disable-next-line missing-zero-check
        token = _token;
        decimalPad = uint96(10 ** IERC20Metadata(token).decimals());
    }

    /// @inheritdoc IBeaconChainBacking
    function update(
        uint208 totalAssets,
        uint208 totalLiabilities,
        uint48 queriedTimestamp
    ) public hasRole(Roles.LSD_BACKING_UPDATER) {
        if (queriedTimestamp < currentRatio.timestamp) {
            revert Errors.InvalidParam("queriedTimestamp");
        }

        uint208 ratio;

        if (totalLiabilities == 0) {
            ratio = 1e18;
        } else {
            ratio = totalAssets * decimalPad / totalLiabilities;
        }
        currentRatio = Ratio(ratio, queriedTimestamp);

        emit RatioUpdated(ratio, totalAssets, totalLiabilities, queriedTimestamp);
    }

    /// @inheritdoc IBeaconChainBacking
    function current() external view returns (uint208 ratio, uint48 queriedTimestamp) {
        ratio = currentRatio.ratio;
        queriedTimestamp = currentRatio.timestamp;
    }
}
