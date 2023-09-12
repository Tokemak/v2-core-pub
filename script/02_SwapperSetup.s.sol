// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems } from "script/BaseScript.sol";

import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { CurveV2Swap } from "src/swapper/adapters/CurveV2Swap.sol";
import { UniV3Swap } from "src/swapper/adapters/UniV3Swap.sol";

/**
 * @dev This script deploys all of the sync swappers in the system.  This script does not
 *      set up swap routes, that must be done through `SetSwapRoute.s.sol`.
 */
contract SwapperSetup is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        BalancerV2Swap balancerSwap = new BalancerV2Swap(constants.sys.swapRouter, constants.ext.balancerVault);
        console.log("Balancer swapper: ", address(balancerSwap));

        CurveV1StableSwap curveV1Swap = new CurveV1StableSwap(constants.sys.swapRouter, constants.tokens.weth);
        console.log("Curve V1 swapper: ", address(curveV1Swap));

        CurveV2Swap curveV2Swap = new CurveV2Swap(constants.sys.swapRouter);
        console.log("Curve V2 swapper: ", address(curveV2Swap));

        UniV3Swap uniV3Swap = new UniV3Swap(constants.sys.swapRouter);
        console.log("Uni V3 swapper: ", address(uniV3Swap));

        vm.stopBroadcast();
    }
}
