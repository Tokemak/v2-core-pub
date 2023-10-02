// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IAsset } from "src/interfaces/external/balancer/IAsset.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IBasePool } from "src/interfaces/external/balancer/IBasePool.sol";
import { BaseAdapter, ISyncSwapper } from "src/swapper/adapters/BaseAdapter.sol";

contract BalancerV2Swap is BaseAdapter {
    using SafeERC20 for IERC20;

    IVault public immutable vault;

    constructor(address _router, address _balancerVault) BaseAdapter(_router) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");
        vault = IVault(_balancerVault);
    }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external view override {
        bytes32 poolId = abi.decode(swapData.data, (bytes32));
        bytes32 id = IBasePool(swapData.pool).getPoolId();

        // verify that the swapData.pool has the same id as the encoded poolId
        if (id != poolId) revert DataMismatch("poolId");

        // verify that the fromAddress and toAddress are in the pool. getPoolTokenInfo will revert if not
        // slither-disable-start low-level-calls,missing-zero-check,unchecked-lowlevel

        string memory funcSelector = "getPoolTokenInfo(bytes32,address)";

        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(vault).staticcall(abi.encodeWithSignature(funcSelector, poolId, fromAddress));
        if (!success) revert DataMismatch("fromAddress");

        (success,) = address(vault).staticcall(abi.encodeWithSignature(funcSelector, poolId, swapData.token));
        if (!success) revert DataMismatch("toAddress");
        // slither-disable-end low-level-calls,missing-zero-check,unchecked-lowlevel
    }

    /// @inheritdoc ISyncSwapper
    function swap(
        address,
        address sellTokenAddress,
        uint256 sellAmount,
        address buyTokenAddress,
        uint256 minBuyAmount,
        bytes memory data
    ) external override onlyRouter returns (uint256) {
        bytes32 poolId = abi.decode(data, (bytes32));

        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap(poolId, IVault.SwapKind.GIVEN_IN, sellTokenAddress, buyTokenAddress, sellAmount, "");

        IVault.FundManagement memory funds = IVault.FundManagement(address(this), false, payable(address(this)), false);

        LibAdapter._approve(IERC20(sellTokenAddress), address(vault), sellAmount);

        return vault.swap(singleSwap, funds, minBuyAmount, block.timestamp);
    }
}
