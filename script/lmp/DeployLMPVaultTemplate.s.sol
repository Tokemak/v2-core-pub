// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { Systems } from "script/utils/Constants.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { AutoPoolFactory } from "src/vault/AutoPoolFactory.sol";

contract AutoPoolSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioAutoPool = 800;
    uint256 public defaultRewardBlockDurationAutoPool = 100;
    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // AutoPool Factory setup.
        AutoPoolETH autoPoolTemplate = new AutoPoolETH(systemRegistry, wethAddress, true);
        console.log("AutoPool Vault WETH Template: %s", address(autoPoolTemplate));

        AutoPoolFactory autoPoolFactory = new AutoPoolFactory(
            systemRegistry, address(autoPoolTemplate), defaultRewardRatioAutoPool, defaultRewardBlockDurationAutoPool
        );
        systemRegistry.setAutoPoolFactory(autoPoolType, address(autoPoolFactory));
        console.log("AutoPool Vault Factory: %s", address(autoPoolFactory));

        vm.stopBroadcast();
    }
}
