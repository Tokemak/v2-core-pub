// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems } from "script/BaseScript.sol";

import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

/// @dev Sets swap route for tokens on `SwapRouter.sol` contract.
contract SetSwapRoute is BaseScript {
    ISwapRouter.SwapData[] public swapDataArray;

    /// @dev Set this.  Asset that swap data is being set for.
    address public assetToken = address(1);

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        /// @dev Set SwapData values here.  Will need to adjust length of arrays.  All arrays must be same length;
        address[1] memory tokens = [wethAddress];
        address[1] memory pools = [constants.pools.balCompSfrxethWstethRethV1];
        ISyncSwapper[1] memory swappers = [ISyncSwapper(address(1))];
        bytes[1] memory data = [bytes("")];

        for (uint256 i = 0; i < tokens.length; ++i) {
            swapDataArray.push(
                ISwapRouter.SwapData({ token: tokens[i], pool: pools[i], swapper: swappers[i], data: data[i] })
            );
        }

        console.log("Swap routes set.");

        ISwapRouter(constants.sys.swapRouter).setSwapRoute(assetToken, swapDataArray);

        vm.stopBroadcast();
    }
}
