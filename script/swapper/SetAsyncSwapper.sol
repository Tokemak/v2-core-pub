// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, Systems } from "script/BaseScript.sol";
import { console } from "forge-std/console.sol";

import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";

contract SetAsyncSwapper is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(systemRegistry);
        systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));
        console.log("Async Swapper Registry address: ", address(asyncSwapperRegistry));

        vm.stopBroadcast();
    }
}
