// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { Systems } from "script/utils/Constants.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";

contract AutopoolSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioAutopool = 800;
    uint256 public defaultRewardBlockDurationAutopool = 100;
    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // Autopool Factory setup.
        AutopoolETH autoPoolTemplate = new AutopoolETH(systemRegistry, wethAddress);
        console.log("Autopool Vault WETH Template: %s", address(autoPoolTemplate));

        AutopoolFactory autoPoolFactory = new AutopoolFactory(
            systemRegistry, address(autoPoolTemplate), defaultRewardRatioAutopool, defaultRewardBlockDurationAutopool
        );
        systemRegistry.setAutopoolFactory(autoPoolType, address(autoPoolFactory));
        console.log("Autopool Vault Factory: %s", address(autoPoolFactory));

        vm.stopBroadcast();
    }
}
