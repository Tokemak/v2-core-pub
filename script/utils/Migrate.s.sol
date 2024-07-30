// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count,no-console

import { Script } from "forge-std/Script.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";
import { IAutopool } from "src/interfaces/vault/IAutopilotRouter.sol";

contract Migrate is Script {
    address public oldAutopool = 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        AutopoolETH pool = AutopoolETH(oldAutopool);

        AutopilotRouter router = AutopilotRouter(payable(0x902b1B5aF7c34A80AC2c2957259b7B1606E606E5));

        pool.approve(address(router), pool.balanceOf(owner));
        router.redeemToDeposit(
            IAutopool(oldAutopool),
            IAutopool(0x49C4719EaCc746b87703F964F09C22751F397BA0),
            owner,
            pool.balanceOf(owner),
            26.3e18
        );

        vm.stopBroadcast();
    }
}
