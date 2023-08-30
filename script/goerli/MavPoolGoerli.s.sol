// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IMavFactory } from "script/interfaces/mav/IMavFactory.sol";
import { IPoolPositionAndRewardFactorySlim } from "script/interfaces/mav/IPoolPositionAndRewardFactorySlim.sol";
import { IPool } from "script/interfaces/mav/IPool.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "script/mocks/ERC20Mock.sol";

import { MAV_POOL_FACTORY_GOERLI, MAV_BOOSTED_POSITION_FACTORY_GOERLI } from "script/utils/Addresses.sol";

contract MavPoolGoerli is Script {
    ERC20Mock public swEth;
    ERC20Mock public weth;
    IERC20 public tokenA;
    IERC20 public tokenB;

    /// @dev These values currently represent the weth / sweth pool on mainnet.  Change for different pools.
    uint256 public fee = 200_000_000_000_000;
    uint256 public tickSpacing = 10;
    int256 public lookBack = 3_600_000_000_000_000_000_000;
    int32 public activeTick = 23; // Current mainnet tick - weth / swEth pool, block 18028783.
    /**
     * @dev These currently match the swEth / weth boosted position at mainnet address
     *       0x07148ecBD607D5f8d1DF72d4Aba16F03a3100d4F.
     */
    uint128[] public binIds = [uint128(49)];
    uint128[] public ratios = [uint128(1_000_000_000_000_000_000)];

    function run() external {
        vm.startBroadcast(vm.envUint("GOERLI_PRIVATE_KEY"));

        // Deploy tokens.
        // TODO: Replace both of the below with addresses of deployed tokens if / when they are deployed on Goerli.
        swEth = new ERC20Mock("Swell Eth - Mock", "swEthMock");
        weth = new ERC20Mock("Wrapped Eth - Mock", "wethMock");

        // Sort tokens.
        tokenA = weth > swEth ? swEth : weth;
        tokenB = weth > swEth ? weth : swEth;

        console.log("swEth: ", address(swEth));
        console.log("Weth: ", address(weth));

        // Create Pool.
        address pool =
            IMavFactory(MAV_POOL_FACTORY_GOERLI).create(fee, tickSpacing, lookBack, activeTick, tokenA, tokenB);

        console.log("Pool address: ", pool);

        // Create boosted position.
        address boostedPosition = IPoolPositionAndRewardFactorySlim(MAV_BOOSTED_POSITION_FACTORY_GOERLI)
            .createPoolPositionAndRewards(IPool(pool), binIds, ratios, false);

        console.log("Boosted position address: ", boostedPosition);

        vm.stopBroadcast();
    }
}
