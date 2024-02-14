// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { IAccessControl } from "openzeppelin-contracts/access/IAccessControl.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";

contract AccessControllerMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockAccessControllerVerifyOwner(
        IAccessController accessController,
        address user,
        bool isOwner
    ) internal {
        if (isOwner) {
            vm.mockCall(
                address(accessController),
                abi.encodeWithSelector(IAccessController.verifyOwner.selector, user),
                abi.encode("")
            );
        } else {
            bytes memory customError = abi.encodeWithSelector(IAccessController.AccessDenied.selector);
            vm.mockCallRevert(
                address(accessController),
                abi.encodeWithSelector(IAccessController.verifyOwner.selector, user),
                customError
            );
        }
    }

    function _mockAccessControllerHasRole(
        IAccessController accessController,
        address user,
        bytes32 role,
        bool hasRole
    ) internal {
        vm.mockCall(
            address(accessController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, role, user),
            abi.encode(hasRole)
        );
    }
}
