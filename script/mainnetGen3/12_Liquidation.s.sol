// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { LiquidationExecutor } from "src/liquidation/LiquidationExecutor.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";

contract LiquidationSetup is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        BaseAsyncSwapper propellerHeadSwapper = new BaseAsyncSwapper(0x14f2b6ca0324cd2B013aD02a7D85541d215e2906);
        console.log("PropellerHead Async Swapper: ", address(propellerHeadSwapper));

        BaseAsyncSwapper liFiSwapper = new BaseAsyncSwapper(0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE);
        console.log("LiFi Async Swapper: ", address(liFiSwapper));

        LiquidationRow lr = new LiquidationRow(constants.sys.systemRegistry);
        console.log("Liquidation Row:", address(lr));

        constants.sys.accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, owner);

        lr.addToWhitelist(constants.sys.asyncSwappers.zeroEx);
        lr.addToWhitelist(address(propellerHeadSwapper));
        lr.addToWhitelist(address(liFiSwapper));

        lr.setPriceMarginBps(600);

        constants.sys.accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, owner);

        LiquidationExecutor executor = new LiquidationExecutor(address(lr));
        console.log("Liquidation Executor: ", address(executor));

        constants.sys.accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, address(executor));

        constants.sys.accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(lr));

        vm.stopBroadcast();
    }
}
