//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Vm } from "forge-std/Vm.sol";

library ReadPlan {
    //slither-disable-next-line too-many-digits
    bytes32 public constant MASK = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    function getPayload(
        Vm vm,
        string memory fileName,
        address adapter
    ) public view returns (bytes32[] memory, bytes[] memory) {
        string memory root = "solver/test/payloads/adapters/";
        string memory path = string.concat(root, fileName);
        string memory data = vm.readFile(path);

        bytes32[] memory commands = vm.parseJsonBytes32Array(data, ".commands");
        bytes[] memory elements = vm.parseJsonBytesArray(data, ".state");

        commands = setCommandsAddress(commands, adapter);

        return (commands, elements);
    }

    function setCommandsAddress(bytes32[] memory commands, address newAddress) public pure returns (bytes32[] memory) {
        bytes32 addressBytes = bytes32(uint256(uint160(newAddress)));

        uint256 length = commands.length;
        bytes32[] memory newCommands = new bytes32[](length);
        for (uint256 i = 0; i < length; ++i) {
            bytes32 command = commands[i];

            // Mask out the address part in the original bytes32
            bytes32 maskedData = command & MASK;
            // Combine the masked data with the new address
            newCommands[i] = maskedData | addressBytes;
        }
        return newCommands;
    }
}
