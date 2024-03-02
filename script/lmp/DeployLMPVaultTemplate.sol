// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Roles } from "src/libs/Roles.sol";

import { LMPVaultRegistry, ILMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultRouter, ILMPVaultRouter } from "src/vault/LMPVaultRouter.sol";

contract LMPSystem is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public defaultRewardRatioLmp = 800;
    uint256 public defaultRewardBlockDurationLmp = 100;
    bytes32 public lmpVaultType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        // LMP Factory setup.
        LMPVault lmpVaultTemplate = new LMPVault(systemRegistry, wethAddress, true);
        console.log("LMP Vault WETH Template: %s", address(lmpVaultTemplate));

        LMPVaultFactory lmpFactory = new LMPVaultFactory(
            systemRegistry, address(lmpVaultTemplate), defaultRewardRatioLmp, defaultRewardBlockDurationLmp
        );
        systemRegistry.setLMPVaultFactory(lmpVaultType, address(lmpFactory));
        console.log("LMP Vault Factory: %s", address(lmpFactory));

        vm.stopBroadcast();
    }
}
