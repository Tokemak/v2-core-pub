// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";

import { BaseScript, Systems, SystemRegistry } from "script/BaseScript.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";
import { Roles } from "src/libs/Roles.sol";

/**
 * @dev Make sure to use the checksum addresses in the RIT_ADDRS var
 */
contract RegisterIncentiveTokens is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        address[] memory tokens = new address[](2);
        tokens[0] = 0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2;
        tokens[1] = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        IncentivePricingStats incentivePricing = IncentivePricingStats(address(systemRegistry.incentivePricing()));
        console.log("IncentivePricingStats: ", address(incentivePricing));

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0)) {
                incentivePricing.setRegisteredToken(tokens[i]);
                console.log("Registered Token: ", tokens[i]);
            } else {
                break;
            }
        }

        vm.stopBroadcast();
    }
}
