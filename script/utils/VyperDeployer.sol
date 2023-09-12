// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-inline-assembly

import { Vm } from "forge-std/Vm.sol";

library VyperDeployer {
    Vm public constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    error ContractNotDeployed();

    /**
     * @notice Deploys Vyper contract.
     * @param path Full file path of precompiled vyper contract.
     * @param constructorArgs Bytes encoded constructor arguments.
     */
    function deployVyperContract(
        string memory path,
        bytes memory constructorArgs
    ) internal returns (address deployedAddress) {
        string memory jsonString = VM.readFile(path);

        bytes memory bytecode = VM.parseJsonBytes(jsonString, ".bytecode");

        if (constructorArgs.length > 0) {
            bytecode = abi.encodePacked(bytecode, constructorArgs);
        }

        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        if (deployedAddress == address(0)) revert ContractNotDeployed();
    }
}
