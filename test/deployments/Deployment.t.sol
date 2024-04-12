// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";

contract DeploymentTest is Test {
    address public owner;
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    DestinationVaultRegistry private _destinationVaultRegistry;

    function setUp() public {
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _accessController = new AccessController(address(_systemRegistry));

        _systemRegistry.setAccessController(address(_accessController));

        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);

        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));
    }

    function testInitialDeployment() public { }
}
