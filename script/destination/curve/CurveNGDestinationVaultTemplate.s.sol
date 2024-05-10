// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string,state-visibility,const-name-snakecase,gas-custom-errors

import { Systems } from "script/utils/Constants.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { CurveNGConvexDestinationVault } from "src/vault/CurveNGConvexDestinationVault.sol";

/**
 * @dev This contract sets up a CurveNGConvexDestinationVault within the system.
 *      1. Checks and ensures the presence of the Destination Template Registry in the system.
 *      2. Whitelists the 'curve-ng-convex' destination vault type if it's not already whitelisted.
 *      3. Deploys a new CurveNGConvexDestinationVault instance with Curve and Convex parameters.
 *      4. Registers the newly created vault instance in the Destination Template Registry.
 */
contract CurveNGDestinationVaultTemplate is BaseScript {
    bytes32 constant dvType = keccak256(abi.encode("curve-ng-convex"));

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast();

        if (address(destinationTemplateRegistry) == address(0)) {
            revert("Destination Template Registry not set");
        }

        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        if (!destinationTemplateRegistry.isWhitelistedDestination(dvType)) {
            destinationTemplateRegistry.addToWhitelist(dvTypes);
        }

        CurveNGConvexDestinationVault dv =
            new CurveNGConvexDestinationVault(systemRegistry, constants.tokens.cvx, constants.ext.convexBooster);
        console.log("Curve NG Convex Destination Vault Template:", address(dv));

        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        destinationTemplateRegistry.register(dvTypes, dvs);

        vm.stopBroadcast();
    }
}
