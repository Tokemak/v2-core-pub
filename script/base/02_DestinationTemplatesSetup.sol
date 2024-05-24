// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Roles } from "src/libs/Roles.sol";

// Contracts
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { Systems } from "../utils/Constants.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { MaverickDestinationVault } from "src/vault/MaverickDestinationVault.sol";

import { Systems, Constants } from "../utils/Constants.sol";

contract DestinationTemplatesSetupScript is Script {
    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        BalancerAuraDestinationVault balVault = new BalancerAuraDestinationVault(
            constants.sys.systemRegistry, address(constants.ext.balancerVault), constants.tokens.aura
        );

        MaverickDestinationVault mavVault = new MaverickDestinationVault(constants.sys.systemRegistry);

        console.log("Bal Aura Vault Template - bal-aura-v1: ", address(balVault));
        console.log("Mav Vault Template: mav-v1", address(mavVault));

        bytes32 balKey = keccak256(abi.encode("bal-aura-v1"));
        bytes32 mavKey = keccak256(abi.encode("mav-v1"));

        console.log("\nbal-aura-v1: ");
        console.logBytes32(balKey);
        console.log("\nmav-v1: ");
        console.logBytes32(mavKey);

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = balKey;
        keys[1] = mavKey;

        address[] memory addresses = new address[](2);
        addresses[0] = address(balVault);
        addresses[1] = address(mavVault);

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        DestinationRegistry destRegistry = DestinationRegistry(constants.sys.destinationTemplateRegistry);
        destRegistry.addToWhitelist(keys);
        destRegistry.register(keys, addresses);

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        console.log("\n\n  **************************************");
        console.log("======================================");
        console.log("Remember to put any libraries that were deployed into the foundry.toml");
        console.log("======================================");
        console.log("**************************************\n\n");

        vm.stopBroadcast();
    }
}
