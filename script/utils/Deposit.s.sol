// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract Deposit is Script {
    address public autoPool = 0x983dCF0F05ce02fAF1151873C11D1A64A77E2F8e;
    uint256 public depositAmount = 9e18;

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        AutopoolETH pool = AutopoolETH(autoPool);

        IWETH9 weth = constants.sys.systemRegistry.weth();
        uint256 currentBalance = weth.balanceOf(owner);
        if (currentBalance < depositAmount) {
            weth.deposit{ value: depositAmount - currentBalance }();
        }
        weth.approve(autoPool, depositAmount);
        pool.deposit(depositAmount, owner);

        vm.stopBroadcast();
    }
}
