// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { BalancerGyroscopeEthOracle } from "src/oracles/providers/BalancerGyroscopeEthOracle.sol";
import { Oracle } from "script/core/Oracle.sol";

contract GyroOracle is Script, Oracle {
    bytes32 public autopoolType = keccak256("lst-guarded-weth-v1");

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        BalancerGyroscopeEthOracle oracle =
            new BalancerGyroscopeEthOracle(constants.sys.systemRegistry, constants.ext.balancerVault);
        console.log("Gyro Oracle", address(oracle));

        _registerPoolMapping(constants.sys.rootPriceOracle, oracle, 0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1, true);

        _registerPoolMapping(constants.sys.rootPriceOracle, oracle, 0xF7A826D47c8E02835D94fb0Aa40F0cC9505cb134, true);

        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }
}
