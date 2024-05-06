// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutoPoolRegistry, IAutoPoolRegistry } from "src/vault/AutoPoolRegistry.sol";
import { AutoPoolFactory } from "src/vault/AutoPoolFactory.sol";
import { AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { AutoPilotRouter, IAutoPilotRouter } from "src/vault/AutoPilotRouter.sol";

/**
 * @dev This contract:
 *      1. Deploys and registers the `AutoPoolRegistry` for managing AutoPool vaults.
 *      2. Deploys a `AutoPoolETH` template.
 *      3. Deploys the `AutoPoolFactory`(using previous vault template and the 'lst-guarded-r1' type).
 *      4. Deploys the `AutoPilotRouter`.
 *      5. Grants the `AutoPoolFactory` the `AUTO_POOL_REGISTRY_UPDATER` role.
 *  This script can be rerun to replace the currently deployed lst-guarded-r1 AutoPool vault factory in the system.
 */
contract AutoPoolSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioAutoPool = 800;
    uint256 public defaultRewardBlockDurationAutoPool = 100;
    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // AutoPool Registry setup.
        IAutoPoolRegistry autoPoolRegistry = systemRegistry.autoPoolRegistry();
        if (address(autoPoolRegistry) != address(0)) {
            console.log("AutoPool Vault Registry already set: %s", address(autoPoolRegistry));
        } else {
            autoPoolRegistry = new AutoPoolRegistry(systemRegistry);
            console.log("AutoPool Vault Registry: %s", address(autoPoolRegistry));
            systemRegistry.setAutoPoolRegistry(address(autoPoolRegistry));
        }

        // AutoPool Factory setup.
        AutoPoolETH autoPoolTemplate = new AutoPoolETH(systemRegistry, wethAddress);
        console.log("AutoPool Vault WETH Template: %s", address(autoPoolTemplate));

        AutoPoolFactory autoPoolFactory = new AutoPoolFactory(
            systemRegistry, address(autoPoolTemplate), defaultRewardRatioAutoPool, defaultRewardBlockDurationAutoPool
        );
        systemRegistry.setAutoPoolFactory(autoPoolType, address(autoPoolFactory));
        console.log("AutoPool Vault Factory: %s", address(autoPoolFactory));

        accessController.setupRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));

        // AutoPool router setup.
        IAutoPilotRouter autoPoolRouter = systemRegistry.autoPoolRouter();
        if (address(autoPoolRouter) != address(0)) {
            console.log("AutoPool Router already set: %s", address(autoPoolRouter));
        } else {
            autoPoolRouter = new AutoPilotRouter(systemRegistry);
            systemRegistry.setAutoPilotRouter(address(autoPoolRouter));
            console.log("AutoPool Router: %s", address(autoPoolRouter));
        }

        vm.stopBroadcast();
    }
}
