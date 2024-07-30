// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
// solhint-disable state-visibility,no-console

contract OracleSetup is Script {
    Constants.Values values;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values = Constants.get(Systems.LST_GEN2_MAINNET);

        values.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        values.sys.rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.swEth, 200);

        values.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }
}
