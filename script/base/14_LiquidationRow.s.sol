// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";

contract LiquidationRowScript is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(constants.ext.zeroExProxy);
        console.log("0x Async Swapper: ", address(zeroExSwapper));

        BaseAsyncSwapper liFiSwapper = new BaseAsyncSwapper(0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE);
        console.log("LiFi Async Swapper: ", address(liFiSwapper));

        LiquidationRow lr = new LiquidationRow(constants.sys.systemRegistry);
        console.log("Liquidation Row:", address(lr));

        constants.sys.accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, owner);

        lr.addToWhitelist(address(zeroExSwapper));
        lr.addToWhitelist(address(liFiSwapper));

        constants.sys.accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, owner);

        vm.stopBroadcast();
    }
}
