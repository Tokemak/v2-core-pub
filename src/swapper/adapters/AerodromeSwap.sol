// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IRouter } from "src/interfaces/external/aerodrome/IRouter.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";

import { BaseAdapter, ISyncSwapper } from "src/swapper/adapters/BaseAdapter.sol";

contract AerodromeSwap is BaseAdapter {
    constructor(address _router) BaseAdapter(_router) { }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external pure override {
        IRouter.Route[] memory routes = abi.decode(swapData.data, (IRouter.Route[]));
        if (fromAddress != routes[0].from) revert DataMismatch("fromToken");
        if (swapData.token != routes[routes.length - 1].to) revert DataMismatch("toToken");

        // TODO: check if aerodromeRouter should be available in this scope
        // address fetchedPool = aerodromeRouter.poolFor(route.from, route.to, route.stable, route.factory);
        // if (fetchedPool != swapData.pool) revert DataMismatch("pool");
    }

    /// @inheritdoc ISyncSwapper
    function swap(
        address routerAddress,
        address sellTokenAddress,
        uint256 sellAmount,
        address,
        uint256 minBuyAmount,
        bytes memory data
    ) external override onlyRouter returns (uint256) {
        LibAdapter._approve(IERC20(sellTokenAddress), routerAddress, sellAmount);

        uint256[] memory amounts = IRouter(routerAddress).swapExactTokensForTokens(
            sellAmount, minBuyAmount, abi.decode(data, (IRouter.Route[])), address(this), block.timestamp
        );

        return amounts[amounts.length - 1];
    }
}
