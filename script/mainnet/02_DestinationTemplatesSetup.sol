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
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { CurveNGConvexDestinationVault } from "src/vault/CurveNGConvexDestinationVault.sol";
import { MaverickDestinationVault } from "src/vault/MaverickDestinationVault.sol";

import { Systems, Constants } from "../utils/Constants.sol";

contract DestinationTemplatesSetupScript is Script {
    bytes32 public balAuraKey = keccak256(abi.encode("bal-aura-v1"));
    bytes32 public balKey = keccak256(abi.encode("bal-v1"));
    bytes32 public curveKey = keccak256(abi.encode("crv-cvx-v1"));
    bytes32 public curveNGKey = keccak256(abi.encode("crv-cvx-ng-v1"));
    bytes32 public mavKey = keccak256(abi.encode("mav-v1"));

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        Constants.Values memory constants = Constants.get(Systems.LST_GEN2_MAINNET);

        BalancerAuraDestinationVault balAuraVault = new BalancerAuraDestinationVault(
            constants.sys.systemRegistry, address(constants.ext.balancerVault), constants.tokens.aura
        );

        BalancerDestinationVault balVault =
            new BalancerDestinationVault(constants.sys.systemRegistry, address(constants.ext.balancerVault));

        CurveConvexDestinationVault curveVault = new CurveConvexDestinationVault(
            constants.sys.systemRegistry, constants.tokens.cvx, constants.ext.convexBooster
        );

        CurveNGConvexDestinationVault curveNGVault = new CurveNGConvexDestinationVault(
            constants.sys.systemRegistry, constants.tokens.cvx, constants.ext.convexBooster
        );

        MaverickDestinationVault mavVault = new MaverickDestinationVault(constants.sys.systemRegistry);

        console.log("Bal Aura Vault Template - bal-aura-v1: ", address(balAuraVault));
        console.log("Bal Vault Template - bal-v1: ", address(balVault));
        console.log("Curve Convex Vault Template - crv-cvx-v1: ", address(curveVault));
        console.log("CurveNG Convex Vault Template - crv-cvx-ng-v1: ", address(curveNGVault));
        console.log("Mav Vault Template: mav-v1", address(mavVault));

        console.log("\nbal-aura-v1: ");
        console.logBytes32(balAuraKey);
        console.log("\nbal-v1: ");
        console.logBytes32(balKey);
        console.log("\ncrv-cvx-v1: ");
        console.logBytes32(curveKey);
        console.log("\ncrv-cvx-ng-v1: ");
        console.logBytes32(curveNGKey);
        console.log("\nmav-v1: ");
        console.logBytes32(mavKey);

        bytes32[] memory keys = new bytes32[](5);
        keys[0] = balAuraKey;
        keys[1] = curveKey;
        keys[2] = curveNGKey;
        keys[3] = mavKey;
        keys[4] = balKey;

        address[] memory addresses = new address[](5);
        addresses[0] = address(balAuraVault);
        addresses[1] = address(curveVault);
        addresses[2] = address(curveNGVault);
        addresses[3] = address(mavVault);
        addresses[4] = address(balVault);

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
