// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { LMPVaultRegistry, ILMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultRouter, ILMPVaultRouter } from "src/vault/LMPVaultRouter.sol";

/**
 * @dev This contract:
 *      1. Deploys and registers the `LMPVaultRegistry` for managing LMP vaults.
 *      2. Deploys a `LMPVault` template.
 *      3. Deploys the `LMPVaultFactory`(using previous vault template and the 'lst-guarded-r1' type).
 *      4. Deploys the `LMPVaultRouter`.
 *      5. Grants the `LMPVaultFactory` the `REGISTRY_UPDATER` role.
 *  This script can be rerun to replace the currently deployed lst-guarded-r1 LMP vault factory in the system.
 */
contract LMPSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioLmp = 800;
    uint256 public defaultRewardBlockDurationLmp = 100;
    bytes32 public lmpVaultType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // LMP Registry setup.
        ILMPVaultRegistry lmpRegistry = systemRegistry.lmpVaultRegistry();
        if (address(lmpRegistry) != address(0)) {
            console.log("LMP Vault Registry already set: %s", address(lmpRegistry));
        } else {
            lmpRegistry = new LMPVaultRegistry(systemRegistry);
            console.log("LMP Vault Registry: %s", address(lmpRegistry));
            systemRegistry.setLMPVaultRegistry(address(lmpRegistry));
        }

        // LMP Factory setup.
        LMPVault lmpVaultTemplate = new LMPVault(systemRegistry, wethAddress, true);
        console.log("LMP Vault WETH Template: %s", address(lmpVaultTemplate));

        LMPVaultFactory lmpFactory = new LMPVaultFactory(
            systemRegistry, address(lmpVaultTemplate), defaultRewardRatioLmp, defaultRewardBlockDurationLmp
        );
        systemRegistry.setLMPVaultFactory(lmpVaultType, address(lmpFactory));
        console.log("LMP Vault Factory: %s", address(lmpFactory));

        accessController.setupRole(Roles.REGISTRY_UPDATER, address(lmpFactory));

        // LMP router setup.
        ILMPVaultRouter lmpRouter = systemRegistry.lmpVaultRouter();
        if (address(lmpRouter) != address(0)) {
            console.log("LMP Router already set: %s", address(lmpRouter));
        } else {
            lmpRouter = new LMPVaultRouter(systemRegistry);
            systemRegistry.setLMPVaultRouter(address(lmpRouter));
            console.log("LMP Router: %s", address(lmpRouter));
        }

        vm.stopBroadcast();
    }
}
