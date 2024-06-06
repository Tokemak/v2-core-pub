// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";

/// @title Destination Vault to proxy a Balancer Pool that goes into Aura
contract BalancerGyroscopeDestinationVault is BalancerAuraDestinationVault {
    constructor(
        ISystemRegistry sysRegistry,
        address _balancerVault,
        address _defaultStakingRewardToken
    ) BalancerAuraDestinationVault(sysRegistry, _balancerVault, _defaultStakingRewardToken) { }
}
