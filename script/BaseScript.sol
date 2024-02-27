// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";

// solhint-disable-next-line no-unused-import
import { console } from "forge-std/console.sol";

// Addresses
import { Constants, Systems } from "./utils/Constants.sol";

// Interfaces
import { SystemRegistry, IDestinationVaultRegistry } from "src/SystemRegistry.sol";
import { IAccessController } from "src/security/AccessController.sol";
import { IDestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IDestinationVaultFactory } from "src/interfaces/vault/IDestinationVaultFactory.sol";

/**
 * @dev Base contract for scripting.  Sets env to either Goerli or Mainnet values.  As of
 *      right now this contract sets all values regardless of whether the inheriting contract uses
 *      them or not.
 */
contract BaseScript is Script {
    Constants.Values public constants;
    SystemRegistry public systemRegistry;
    IAccessController public accessController;
    IDestinationRegistry public destinationTemplateRegistry;
    IDestinationVaultFactory public destinationVaultFactory;
    IDestinationVaultRegistry public destinationVaultRegistry;

    // Set based on MAINNET flag.
    address public wethAddress;
    address public tokeAddress;
    address public curveMetaRegistryAddress;
    uint256 public privateKey;

    function setUp(Systems system) internal {
        constants = Constants.get(system);
        wethAddress = constants.tokens.weth;
        tokeAddress = constants.tokens.toke;
        curveMetaRegistryAddress = constants.ext.curveMetaRegistry;
        privateKey = vm.envUint(constants.privateKeyEnvVar);

        systemRegistry = SystemRegistry(constants.sys.systemRegistry);
        accessController = systemRegistry.accessController();
        destinationTemplateRegistry = systemRegistry.destinationTemplateRegistry();
        destinationVaultRegistry = systemRegistry.destinationVaultRegistry();

        if (address(destinationVaultRegistry) != address(0)) {
            destinationVaultFactory = destinationVaultRegistry.factory();
        }
    }
}
