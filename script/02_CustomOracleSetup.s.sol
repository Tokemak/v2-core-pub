// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems } from "script/BaseScript.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

/// @dev Deploys `CustomSetOracle.sol`.  Make sure to set address in `Constants.sol` after launch.
contract CustomOracleSetup is BaseScript {
    /// @dev Set to deisred max age for prices.
    uint256 public constant MAX_AGE = 1 weeks; // TODO: Change to desired value.

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        CustomSetOracle customSet = new CustomSetOracle(systemRegistry, MAX_AGE);

        console.log("Custom Set Oracle: ", address(customSet));

        vm.stopBroadcast();
    }
}
