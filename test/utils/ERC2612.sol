// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Vm } from "forge-std/Vm.sol";

library ERC2612 {
    /// @notice Calculate a 2612 permit signature
    /// @param domainSeparator The EIP712Domain of the verifying contract
    /// @param signerKey Private key of the owner
    /// @param owner Owner of the tokens being sent
    /// @param spender Spender of the tokens
    /// @param value Amount of tokens being sent
    /// @param nonce Next available permit nonce to use
    /// @param deadline Latest the permit is valid for
    /// @return v Component of the secp256k1 signature
    /// @return r Component of the secp256k1 signature
    /// @return s Component of the secp256k1 signature
    function getPermitSignature(
        bytes32 domainSeparator,
        uint256 signerKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) public pure returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 typeHash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01", domainSeparator, keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline))
            )
        );
        (v, r, s) = Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).sign(signerKey, digest);
    }
}
