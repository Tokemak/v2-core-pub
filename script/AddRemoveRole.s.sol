// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Systems } from "./utils/Constants.sol";
import { BaseScript } from "./BaseScript.sol";

// Libraries
// solhint-disable-next-line no-unused-import
import { Roles } from "src/libs/Roles.sol";

// Interfaces
import { IAccessController } from "src/interfaces/security/IAccessController.sol";

/**
 * @dev STATE VARIABLES MUST BE MANUALLY SET! DO NOT BROADCAST THIS SCRIPT TO MAINNET WITHOUT
 *      FIRST CHECKING THESE VARIABLES!
 *
 * @dev This script is used to grant and remove roles in the system.
 *
 * @dev See `01_SystemDeploy.s.sol` for a more detailed overview on scripting.
 */
contract AddRemoveRole is BaseScript {
    ///@dev Manually set variables below.
    bool public constant ADD_ROLE = true; // True to add role, false to remove.
    bytes32[] public rolesToGrantOrRemove = [Roles.ORACLE_MANAGER_ROLE];
    address public roleAddress = address(0);

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));
        roleAddress = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        IAccessController accessControl = IAccessController(constants.sys.accessController);

        for (uint256 i = 0; i < rolesToGrantOrRemove.length; ++i) {
            bytes32 role = rolesToGrantOrRemove[i];
            if (ADD_ROLE) {
                accessControl.setupRole(role, roleAddress);
            } else {
                accessControl.revokeRole(role, roleAddress);
            }
        }
        vm.stopBroadcast();
    }
}
