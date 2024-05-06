// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

contract SystemComponent is ISystemComponent {
    ISystemRegistry internal immutable systemRegistry;

    constructor(ISystemRegistry _systemRegistry) {
        Errors.verifyNotZero(address(_systemRegistry), "_systemRegistry");
        systemRegistry = _systemRegistry;
    }

    /// @inheritdoc ISystemComponent
    function getSystemRegistry() external view returns (address) {
        return address(systemRegistry);
    }

    function _verifySystemRegistry(address _registryToVerify) internal view {
        if (address(systemRegistry) != _registryToVerify) {
            revert Errors.SystemMismatch(address(systemRegistry), _registryToVerify);
        }
    }
}
