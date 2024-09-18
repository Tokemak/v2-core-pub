// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";

contract Deposit is Script {
    address public autoPool = 0x72cf6d7C85FfD73F18a83989E7BA8C1c30211b73;
    uint256 public redeemAmount = 1e18;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        AutopoolETH pool = AutopoolETH(autoPool);

        pool.redeem(redeemAmount, owner, owner);

        vm.stopBroadcast();
    }
}
