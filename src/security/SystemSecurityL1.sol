// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SystemSecurity, ISystemSecurity } from "src/security/SystemSecurity.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract SystemSecurityL1 is ISystemSecurity, SystemSecurity {
    constructor(ISystemRegistry _systemRegistry) SystemSecurity(_systemRegistry) { }

    /// @inheritdoc ISystemSecurity
    function isSystemPaused() external view override returns (bool) {
        return _systemPaused;
    }
}
