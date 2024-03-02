// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";

/**
 * @dev This contract is designed to deploy and configure key components of the Destination System.
 * - Deploys and registers the `DestinationRegistry` for managing destination templates.
 * - Deploys and registers the `DestinationVaultRegistry` for tracking destination vaults.
 * - Deploys and sets up the `DestinationVaultFactory` with specified reward configurations.
 * - Grants the `CREATE_DESTINATION_VAULT_ROLE` role to the deploying wallet, enabling the creation of new destination
 * vaults.
 */
contract DestinationSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardBlockDuration = 1000;
    uint256 public defaultRewardRatio = 1;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        address owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        vm.startBroadcast(privateKey);

        // Destination registry setup.
        DestinationRegistry destRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destRegistry));
        console.log("Destination Template Registry: %s", address(destRegistry));

        DestinationVaultRegistry destVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destVaultRegistry));
        console.log("Destination Vault Registry: %s", address(destVaultRegistry));

        // Destination vault factory setup.
        DestinationVaultFactory destVaultFactory =
            new DestinationVaultFactory(systemRegistry, defaultRewardRatio, defaultRewardBlockDuration);
        destVaultRegistry.setVaultFactory(address(destVaultFactory));
        console.log("Destination Vault Factory: %s", address(destVaultFactory));

        accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, owner);

        vm.stopBroadcast();
    }
}
