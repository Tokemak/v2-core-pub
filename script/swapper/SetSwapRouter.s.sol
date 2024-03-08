// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, Systems } from "script/BaseScript.sol";
import { console } from "forge-std/console.sol";

import { SwapRouter } from "src/swapper/SwapRouter.sol";

contract SetSwapRouter is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        SwapRouter swapRouter = new SwapRouter(systemRegistry);
        systemRegistry.setSwapRouter(address(swapRouter));
        console.log("Swap Router: ", address(swapRouter));

        vm.stopBroadcast();
    }
}
