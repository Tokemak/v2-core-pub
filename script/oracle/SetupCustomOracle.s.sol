// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems, SystemRegistry } from "script/BaseScript.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { RootPriceOracle, IPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { Roles } from "src/libs/Roles.sol";

/**
 * @dev This script sets token addresses and max ages on `CustomSetOracle.sol`, as well as setting
 *      the custom set oracle as the price oracle for the token on `RootPriceOracle.sol`.
 *
 * @dev Set state variables before running script against mainnet.
 */
contract SetupCustomOracle is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        /// @dev Set tokens and max ages here.
        address[] memory tokens = new address[](1);
        uint256[] memory maxAges = new uint256[](1);

        tokens[0] = constants.tokens.aura;
        maxAges[0] = 1 days;

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));
        address owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        accessController.grantRole(Roles.ORACLE_MANAGER_ROLE, owner);
        accessController.grantRole(Roles.CUSTOM_ORACLE_EXECUTOR, owner);

        CustomSetOracle oracle = new CustomSetOracle(systemRegistry, 1 days);
        console.log("Custom Set Oracle: ", address(oracle));

        // Register tokens on `CustomSetOracle.sol`
        CustomSetOracle(oracle).registerTokens(tokens, maxAges);
        console.log("Tokens registered on CustomSetOracle.sol.");

        // Set tokens on `RootPriceOracle.sol`.
        RootPriceOracle rootPrice =
            RootPriceOracle(address(SystemRegistry(constants.sys.systemRegistry).rootPriceOracle()));
        for (uint256 i = 0; i < tokens.length; ++i) {
            rootPrice.registerMapping(tokens[i], oracle);
        }
        console.log("Tokens registered on RootPriceOracle with CustomSetOracle as price oracle.");

        vm.stopBroadcast();
    }
}
