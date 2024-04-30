// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { console } from "forge-std/console.sol";
import { BaseScript } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";

contract SetupLiquidation is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        address owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        vm.startBroadcast(privateKey);

        accessController.grantRole(Roles.LMP_VAULT_REGISTRY_UPDATER, owner);
        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(constants.ext.zeroExProxy);
        console.log("Base Async Swapper: ", address(zeroExSwapper));

        LiquidationRow lr = new LiquidationRow(systemRegistry);
        console.log("Liquidation Row:", address(lr));

        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(lr));
        accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, owner);
        accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, owner);

        lr.addToWhitelist(address(zeroExSwapper));

        vm.stopBroadcast();
    }
}
