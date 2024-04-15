// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, Systems } from "script/BaseScript.sol";

import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";

contract SetCurveRoutesSet1 is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        SwapRouter swapRouter = SwapRouter(payable(address(systemRegistry.swapRouter())));
        CurveV1StableSwap curveV1Swap = new CurveV1StableSwap(address(swapRouter), address(systemRegistry.weth()));

        // route STETH_MAINNET -> ETH
        ISwapRouter.SwapData[] memory stEthToEthRoute = new ISwapRouter.SwapData[](1);
        stEthToEthRoute[0] = ISwapRouter.SwapData({
            token: address(systemRegistry.weth()),
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            swapper: curveV1Swap,
            data: abi.encode(1, 0) // SellIndex, BuyIndex
         });
        swapRouter.setSwapRoute(constants.tokens.stEth, stEthToEthRoute);

        vm.stopBroadcast();
    }
}
