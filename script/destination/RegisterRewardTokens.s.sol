// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Roles } from "src/libs/Roles.sol";

import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";

/**
 * @dev This script is used to register reward tokens in the Tokemak system.
 * It checks if the specified tokens (WETH and TOKE) are already registered as reward tokens.
 * If not, it registers them as reward tokens using the systemRegistry contract.
 */
contract RegisterRewardTokens is BaseScript {
    uint256 public defaultRewardBlockDurationDest = 1000;
    uint256 public defaultRewardRatioDest = 1;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        if (systemRegistry.isRewardToken(constants.tokens.weth)) {
            console.log("WETH is already registered as a reward token");
        } else {
            console.log("WETH is not registered as a reward token");
            console.log("Registering WETH as a reward token");
            systemRegistry.addRewardToken(constants.tokens.weth);
        }

        if (systemRegistry.isRewardToken(constants.tokens.toke)) {
            console.log("TOKE is already registered as a reward token");
        } else {
            console.log("TOKE is not registered as a reward token");
            console.log("Registering TOKE as a reward token");
            systemRegistry.addRewardToken(constants.tokens.toke);
        }

        vm.stopBroadcast();
    }
}
