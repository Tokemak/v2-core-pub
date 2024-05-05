// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import { IAsyncSwapperRegistry } from "src/interfaces/liquidation/IAsyncSwapperRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract AsyncSwapperRegistry is SystemComponent, IAsyncSwapperRegistry, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _swappers;

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    function register(address swapperAddress) external override hasRole(Roles.AUTO_POOL_REGISTRY_UPDATER) {
        Errors.verifyNotZero(swapperAddress, "swapperAddress");

        if (!_swappers.add(swapperAddress)) revert Errors.ItemExists();

        emit SwapperAdded(swapperAddress);
    }

    function unregister(address swapperAddress) external override hasRole(Roles.AUTO_POOL_REGISTRY_UPDATER) {
        Errors.verifyNotZero(swapperAddress, "swapperAddress");

        if (!_swappers.remove(swapperAddress)) revert Errors.ItemNotFound();

        emit SwapperRemoved(swapperAddress);
    }

    function isRegistered(address swapperAddress) external view override returns (bool) {
        return _swappers.contains(swapperAddress);
    }

    function verifyIsRegistered(address swapperAddress) external view override {
        if (!_swappers.contains(swapperAddress)) revert Errors.NotRegistered();
    }

    function list() external view override returns (address[] memory) {
        return _swappers.values();
    }
}
