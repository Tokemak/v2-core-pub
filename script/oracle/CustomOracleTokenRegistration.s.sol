// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems, SystemRegistry } from "script/BaseScript.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { RootPriceOracle, IPriceOracle } from "src/oracles/RootPriceOracle.sol";

/**
 * @dev This script sets token addresses and max ages on `CustomSetOracle.sol`, as well as setting
 *      the custom set oracle as the price oracle for the token on `RootPriceOracle.sol`.
 *
 * @dev Set state variables before running script against mainnet.
 */
contract CustomSetOracleTokenRegistration is BaseScript {
    /// @dev Set tokens and max ages here.
    address[] public tokens = [address(1)];
    uint256[] public maxAges = [1 days];

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        // Register tokens on `CustomSetOracle.sol`
        CustomSetOracle(constants.sys.customSetOracle).registerTokens(tokens, maxAges);
        console.log("Tokens registered on CustomSetOracle.sol.");

        // Set tokens on `RootPriceOracle.sol`.
        IPriceOracle customSet = IPriceOracle(constants.sys.customSetOracle);
        RootPriceOracle rootPrice =
            RootPriceOracle(address(SystemRegistry(constants.sys.systemRegistry).rootPriceOracle()));
        for (uint256 i = 0; i < tokens.length; ++i) {
            rootPrice.registerMapping(tokens[i], customSet);
        }
        console.log("Tokens registered on RootPriceOracle with CustomSetOracle as price oracle.");

        vm.stopBroadcast();
    }
}
