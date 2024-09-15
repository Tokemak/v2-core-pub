// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { ChainlinkIncentivePricesUpkeepV3 } from "src/stats/ChainlinkIncentivePricesUpkeepV3.sol";

contract IncentivePricingRegistration is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, owner);

        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.wstEth);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.crv);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.cvx);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.ldo);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.stEth);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.aura);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.swise);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.rpl);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.bal);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.usdc);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.toke);
        constants.sys.incentivePricing.setRegisteredToken(constants.tokens.dinero);

        constants.sys.accessController.revokeRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, owner);

        ChainlinkIncentivePricesUpkeepV3 upKeep = new ChainlinkIncentivePricesUpkeepV3();
        console.log("Chainlink Incentive Prices Upkeep: ", address(upKeep));

        constants.sys.accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(upKeep));

        vm.stopBroadcast();
    }
}
