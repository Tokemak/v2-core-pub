// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems, SystemRegistry } from "script/BaseScript.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";

/**
 * @dev Set state variables before running script against mainnet.
 */
contract RegisterCustomOracleToken is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        /// @dev Set tokens and max ages here.
        address[] memory tokens = new address[](1);
        uint256[] memory maxAges = new uint256[](1);

        tokens[0] = address(uint160(vm.envUint("RCOT_TOKEN")));
        maxAges[0] = vm.envUint("RCOT_MAXAGE");

        console.log("Registering Token: ", tokens[0]);
        console.log("Registering Token With Age: ", maxAges[0]);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        CustomSetOracle oracle = CustomSetOracle(constants.sys.subOracles.customSet);
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
