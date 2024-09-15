// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolMainRewarder } from "src/rewarders/AutopoolMainRewarder.sol";

contract AddTokeRewards is Script {
    AutopoolETH public autoPool = AutopoolETH(0xadEe3Fd7D10Ed834175Da327b95755B879194a03);
    uint256 public amount = 10e18;

    function run() external {
        Constants.Values memory values = Constants.get(Systems.LST_GEN1_SEPOLIA);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values.sys.accessController.grantRole(Roles.AUTO_POOL_REWARD_MANAGER, owner);

        AutopoolMainRewarder rewarder = AutopoolMainRewarder(address(autoPool.rewarder()));

        //rewarder.addToWhitelist(owner);

        values.sys.systemRegistry.toke().approve(address(rewarder), amount);
        rewarder.queueNewRewards(amount);

        vm.stopBroadcast();
    }
}
