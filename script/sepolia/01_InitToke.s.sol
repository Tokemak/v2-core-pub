// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract InitToke is Script {
    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        address testnetToke = address(new TestnetToke());
        console.log("TOKE: ", testnetToke);
        console.log("Balance holder: ", owner);

        vm.stopBroadcast();
    }
}

contract TestnetToke is ERC20 {
    constructor() ERC20("Tokemak", "TOKE") {
        _mint(msg.sender, 100_000_000e18);
    }
}
