// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { LMPVaultRouter } from "src/vault/LMPVaultRouter.sol";
import { IERC20, SafeERC20, Address } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract DeploySystem is Script {
    function run() external {
        IWETH9 weth = IWETH9(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
        uint256 allowance =
            weth.allowance(0x6b473f966de102fE733cF5ed7163EbB7B13Ad889, 0x793361c56d86C94343248e6EDCb1cF41fC85AddE);

        console.log(allowance);

        //LMPVaultRouter router = LMPVaultRouter(payable(0x6b473f966de102fE733cF5ed7163EbB7B13Ad889));

        // vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // router.approve(IERC20(address(weth)), 0x793361c56d86C94343248e6EDCb1cF41fC85AddE, 0);
        // vm.stopBroadcast();
    }
}
