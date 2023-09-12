// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems } from "script/BaseScript.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

/**
 * @dev This script is used to set token prices on `CustomSetOracle.sol`.  Custom set oracle must
 *      be deployed and set in `Constants.sol`.
 *
 * @dev Make sure to change state variables before running script.
 */
contract CustomOracleSetPrice is BaseScript {
    /// @dev Set tokens, prices, timestamps here
    address[] public tokens = [wethAddress];
    uint256[] public ethPrices = [1_000_000_000_000_000_000];
    uint256[] public queriedTimestamps = [block.timestamp];

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        CustomSetOracle(constants.sys.customSetOracle).setPrices(tokens, ethPrices, queriedTimestamps);

        console.log("Prices set.");

        vm.stopBroadcast();
    }
}
