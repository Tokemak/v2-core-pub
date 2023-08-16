// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript } from "./BaseScript.sol";
import { Systems } from "./utils/Constants.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";

/**
 * @dev STATE VARIABLE MUST BE MANUALLY SET! DO NOT BROADCAST TO MAINNET WITHOUT FIRST CHECKING STATE
 *      VARIABLES!
 *
 * @dev This script allows a privileged address to add, replace and remove destination templates, as well
 *      as to add and remove destination types from the whitelist.
 *
 * @dev See `01_SystemDeploy.s.sol` for more information on running scripts.
 */
contract DestinationTemplateScripts is BaseScript {
    enum Action {
        AddTemplate,
        ReplaceTemplate,
        RemoveTemplate,
        AddWhitelist,
        RemoveWhitelist
    }

    /// @dev Manually set variables below.
    Action public action = Action.AddTemplate;
    bytes32[] public destinationTypes = [bytes32(0)];
    address[] public destinationAddresses = [address(0)];

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        IDestinationRegistry destinationRegistry = IDestinationRegistry(destinationTemplateRegistry);

        vm.startBroadcast(privateKey);

        if (action == Action.AddTemplate) {
            destinationRegistry.register(destinationTypes, destinationAddresses);
        } else if (action == Action.ReplaceTemplate) {
            destinationRegistry.replace(destinationTypes, destinationAddresses);
        } else if (action == Action.RemoveTemplate) {
            destinationRegistry.unregister(destinationTypes);
        } else if (action == Action.AddWhitelist) {
            destinationRegistry.addToWhitelist(destinationTypes);
        } else if (action == Action.RemoveWhitelist) {
            destinationRegistry.removeFromWhitelist(destinationTypes);
        }

        vm.stopBroadcast();
    }
}
