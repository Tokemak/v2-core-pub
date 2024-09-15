// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { CurveV2Swap } from "src/swapper/adapters/CurveV2Swap.sol";
import { UniV3Swap } from "src/swapper/adapters/UniV3Swap.sol";

contract SwapRouterSwappers is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        BalancerV2Swap balancerSwap = new BalancerV2Swap(constants.sys.swapRouter, address(constants.ext.balancerVault));
        console.log("Balancer Swapper: ", address(balancerSwap));

        CurveV1StableSwap curveV1Swap = new CurveV1StableSwap(constants.sys.swapRouter, constants.tokens.weth);
        console.log("Curve V1 Swapper: ", address(curveV1Swap));

        CurveV2Swap curveV2Swap = new CurveV2Swap(constants.sys.swapRouter);
        console.log("Curve V2 Swapper: ", address(curveV2Swap));

        UniV3Swap uniV3Swap = new UniV3Swap(constants.sys.swapRouter);
        console.log("Uni V3 Swapper: ", address(uniV3Swap));

        vm.stopBroadcast();
    }
}
