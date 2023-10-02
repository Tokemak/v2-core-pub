// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { ICurveV2Swap } from "src/interfaces/external/curve/ICurveV2Swap.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { BaseAdapter, ISyncSwapper } from "src/swapper/adapters/BaseAdapter.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

contract CurveV2Swap is BaseAdapter {
    using SafeERC20 for IERC20;

    constructor(address _router) BaseAdapter(_router) { }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external view override {
        (uint256 sellIndex, uint256 buyIndex) = abi.decode(swapData.data, (uint256, uint256));

        ICurveV2Swap pool = ICurveV2Swap(swapData.pool);

        address sellAddress = pool.coins(sellIndex);
        address buyAddress = pool.coins(buyIndex);

        // verify that the fromAddress and toAddress are in the pool
        if (fromAddress != sellAddress) revert DataMismatch("fromAddress");
        if (swapData.token != buyAddress) revert DataMismatch("toAddress");
    }

    /// @inheritdoc ISyncSwapper
    function swap(
        address poolAddress,
        address sellTokenAddress,
        uint256 sellAmount,
        address,
        uint256 minBuyAmount,
        bytes memory data
    ) external override onlyRouter returns (uint256) {
        (uint256 sellIndex, uint256 buyIndex) = abi.decode(data, (uint256, uint256));
        ICurveV2Swap pool = ICurveV2Swap(poolAddress);

        LibAdapter._approve(IERC20(sellTokenAddress), poolAddress, sellAmount);

        return pool.exchange(sellIndex, buyIndex, sellAmount, minBuyAmount);
    }
}
