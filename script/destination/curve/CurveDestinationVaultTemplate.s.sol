// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemSecurity } from "src/security/SystemSecurity.sol";

import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";

/**
 * @dev This contract sets up a CurveConvexDestinationVault within the system.
 *      1. Checks and ensures the presence of the Destination Template Registry in the system.
 *      2. Whitelists the 'curve-convex' destination vault type if it's not already whitelisted.
 *      3. Deploys a new CurveConvexDestinationVault instance with Curve and Convex parameters.
 *      4. Registers the newly created vault instance in the Destination Template Registry.
 */
contract CurveDestinationVaultTemplate is BaseScript {
    bytes32 constant dvType = keccak256(abi.encode("curve-convex"));

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        if (address(destinationTemplateRegistry) == address(0)) {
            revert("Destination Template Registry not set");
        }

        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        if (!destinationTemplateRegistry.isWhitelistedDestination(dvType)) {
            destinationTemplateRegistry.addToWhitelist(dvTypes);
        }

        CurveConvexDestinationVault dv =
            new CurveConvexDestinationVault(systemRegistry, constants.tokens.cvx, constants.ext.convexBooster);
        console.log("Curve Convex Destination Vault Template:", address(dv));

        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        destinationTemplateRegistry.register(dvTypes, dvs);

        vm.stopBroadcast();
    }
}
