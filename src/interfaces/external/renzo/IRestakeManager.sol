// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IRestakeManager {
    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);
}
