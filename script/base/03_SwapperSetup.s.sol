// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { UniV3Swap } from "src/swapper/adapters/UniV3Swap.sol";

/**
 * @dev This script deploys all of the sync swappers in the system.  This script does not
 *      set up swap routes, that must be done through `SetSwapRoute.s.sol`.
 */
contract SwapperSetup is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        BalancerV2Swap balancerSwap = new BalancerV2Swap(constants.sys.swapRouter, address(constants.ext.balancerVault));
        console.log("Balancer swapper: ", address(balancerSwap));

        UniV3Swap uniV3Swap = new UniV3Swap(constants.sys.swapRouter);
        console.log("Uni V3 swapper: ", address(uniV3Swap));

        vm.stopBroadcast();
    }
}
