// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPositionMetadata {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
