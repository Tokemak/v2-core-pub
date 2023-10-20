// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { CommandBuilder } from "src/solver/CommandBuilder.sol";

// solhint-disable avoid-low-level-calls
// solhint-disable no-inline-assembly
// slither-disable-start delegatecall-loop,low-level-calls,assembly,dead-code

/**
 *
 * @dev This contract is based on the Weiroll project (https://github.com/weiroll/weiroll),
 * with a critical bug fix applied from the following fork:
 * https://github.com/georgercarder/weiroll/tree/george/audit/issue/critical/17
 *
 * The original Weiroll project has an unmerged bug fix
 * (https://github.com/weiroll/weiroll/pull/86) which could lead to potential vulnerabilities.
 * In order to ensure the proper functionality of the contract, the bug fix from George Carder's fork has been
 * incorporated.
 */
abstract contract VM {
    using CommandBuilder for bytes[];

    uint256 private constant FLAG_CT_DELEGATECALL = 0x00;
    uint256 private constant FLAG_CT_CALL = 0x01;
    uint256 private constant FLAG_CT_STATICCALL = 0x02;
    uint256 private constant FLAG_CT_VALUECALL = 0x03;
    uint256 private constant FLAG_CT_MASK = 0x03;
    uint256 private constant FLAG_EXTENDED_COMMAND = 0x40;
    uint256 private constant FLAG_TUPLE_RETURN = 0x80;

    // slither-disable-next-line too-many-digits
    uint256 private constant SHORT_COMMAND_FILL = 0x000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    address private immutable self;

    error ExecutionFailed();
    // Error thrown when value call has no value indicated.
    error ValueCallNoValueIndicated();
    error InvalidCalltype();

    constructor() {
        self = address(this);
    }

    function _execute(bytes32[] calldata commands, bytes[] memory state) internal returns (bytes[] memory) {
        bytes32 command;
        uint256 flags;
        bytes32 indices;

        bool success;
        bytes memory outdata;

        uint256 commandsLength = commands.length;
        for (uint256 i; i < commandsLength; i = _uncheckedIncrement(i)) {
            command = commands[i];

            flags = uint256(command >> 216) & 0xFF; // more efficient
            // flags = uint256(uint8(bytes1(command << 32))); // more readable

            if (flags & FLAG_EXTENDED_COMMAND != 0) {
                indices = commands[++i];
            } else {
                indices = bytes32(uint256(command << 40) | SHORT_COMMAND_FILL);
            }

            if (flags & FLAG_CT_MASK == FLAG_CT_DELEGATECALL) {
                // slither-disable-next-line controlled-delegatecall
                (success, outdata) = address(uint160(uint256(command))).delegatecall( // target
                    // inputs
                    state.buildInputs(
                        //selector
                        bytes4(command),
                        indices
                    )
                );
            } else if (flags & FLAG_CT_MASK == FLAG_CT_CALL) {
                (success, outdata) = address(uint160(uint256(command))).call( // target
                    // inputs
                    state.buildInputs(
                        //selector
                        bytes4(command),
                        indices
                    )
                );
            } else if (flags & FLAG_CT_MASK == FLAG_CT_STATICCALL) {
                (success, outdata) = address(uint160(uint256(command))).staticcall( // target
                    // inputs
                    state.buildInputs(
                        //selector
                        bytes4(command),
                        indices
                    )
                );
            } else if (flags & FLAG_CT_MASK == FLAG_CT_VALUECALL) {
                uint256 callEth;
                bytes memory v = state[uint8(bytes1(indices))];
                if (v.length != 32) {
                    revert ValueCallNoValueIndicated();
                }
                assembly {
                    callEth := mload(add(v, 0x20))
                }
                (success, outdata) = address(uint160(uint256(command))).call{ value: callEth }( // target
                    // inputs
                    state.buildInputs(
                        //selector
                        bytes4(command),
                        bytes32(uint256(indices << 8) | CommandBuilder.IDX_END_OF_ARGS)
                    )
                );
            } else {
                revert InvalidCalltype();
            }

            if (!success) {
                if (outdata.length == 0) revert ExecutionFailed();

                assembly {
                    revert(add(32, outdata), mload(outdata))
                }
            }

            if (flags & FLAG_TUPLE_RETURN != 0) {
                state.writeTuple(bytes1(command << 88), outdata);
            } else {
                state = state.writeOutputs(bytes1(command << 88), outdata);
            }
        }
        return state;
    }

    function _uncheckedIncrement(uint256 i) private pure returns (uint256) {
        unchecked {
            ++i;
        }
        return i;
    }
}

// slither-disable-end delegatecall-loop,low-level-calls,assembly,dead-code
