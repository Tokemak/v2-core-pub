// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolRegistry, IAutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopilotRouter, IAutopilotRouter } from "src/vault/AutopilotRouter.sol";

/**
 * @dev This contract:
 *      1. Deploys and registers the `AutopoolRegistry` for managing Autopool vaults.
 *      2. Deploys a `AutopoolETH` template.
 *      3. Deploys the `AutopoolFactory`(using previous vault template and the 'lst-guarded-r1' type).
 *      4. Deploys the `AutopilotRouter`.
 *      5. Grants the `AutopoolFactory` the `AUTO_POOL_REGISTRY_UPDATER` role.
 *  This script can be rerun to replace the currently deployed lst-guarded-r1 Autopool vault factory in the system.
 */
contract AutopoolSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioAutopool = 800;
    uint256 public defaultRewardBlockDurationAutopool = 100;
    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // Autopool Registry setup.
        IAutopoolRegistry autoPoolRegistry = systemRegistry.autoPoolRegistry();
        if (address(autoPoolRegistry) != address(0)) {
            console.log("Autopool Vault Registry already set: %s", address(autoPoolRegistry));
        } else {
            autoPoolRegistry = new AutopoolRegistry(systemRegistry);
            console.log("Autopool Vault Registry: %s", address(autoPoolRegistry));
            systemRegistry.setAutopoolRegistry(address(autoPoolRegistry));
        }

        // Autopool Factory setup.
        AutopoolETH autoPoolTemplate = new AutopoolETH(systemRegistry, wethAddress);
        console.log("Autopool Vault WETH Template: %s", address(autoPoolTemplate));

        AutopoolFactory autoPoolFactory = new AutopoolFactory(
            systemRegistry, address(autoPoolTemplate), defaultRewardRatioAutopool, defaultRewardBlockDurationAutopool
        );
        systemRegistry.setAutopoolFactory(autoPoolType, address(autoPoolFactory));
        console.log("Autopool Vault Factory: %s", address(autoPoolFactory));

        accessController.setupRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));

        // Autopool router setup.
        IAutopilotRouter autoPoolRouter = systemRegistry.autoPoolRouter();
        if (address(autoPoolRouter) != address(0)) {
            console.log("Autopool Router already set: %s", address(autoPoolRouter));
        } else {
            autoPoolRouter = new AutopilotRouter(systemRegistry);
            systemRegistry.setAutopilotRouter(address(autoPoolRouter));
            console.log("Autopool Router: %s", address(autoPoolRouter));
        }

        vm.stopBroadcast();
    }
}
