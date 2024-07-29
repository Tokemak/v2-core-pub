// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

contract DestinationVaultRegistryMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockDestVaultRegVerifyIsRegistered(
        IDestinationVaultRegistry destinationVaultRegistry,
        address destinationVault,
        bool isRegistered
    ) internal {
        if (isRegistered) {
            vm.mockCall(
                address(destinationVaultRegistry),
                abi.encodeWithSelector(IDestinationVaultRegistry.verifyIsRegistered.selector, destinationVault),
                abi.encode("")
            );
        } else {
            bytes memory customError = abi.encodeWithSelector(Errors.NotRegistered.selector);

            // Bug in Foundry right now where the mockCallRevert() can't be the only mockCall made so we're just
            // setting it and then immediately replacing it
            vm.mockCall(
                address(destinationVaultRegistry),
                abi.encodeWithSelector(IDestinationVaultRegistry.verifyIsRegistered.selector, destinationVault),
                abi.encode("")
            );
            vm.mockCallRevert(
                address(destinationVaultRegistry),
                abi.encodeWithSelector(IDestinationVaultRegistry.verifyIsRegistered.selector, destinationVault),
                customError
            );
        }
    }
}
