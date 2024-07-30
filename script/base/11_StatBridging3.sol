// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { Calculators } from "script/core/Calculators.sol";

contract StatBridging is Script, Calculators {
    Constants.Values public constants;

    bytes32 internal bridgedLstTemplateId = keccak256("lst-bridged");

    uint64 public ccipMainnetChainSelector = 5_009_297_550_715_157_269;

    constructor() Calculators(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        Constants.Tokens memory mainnetTokens = Constants.getMainnetTokens();

        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);

        constants.sys.ethPerTokenStore.registerToken(mainnetTokens.weEth);

        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        vm.stopBroadcast();
    }
}
