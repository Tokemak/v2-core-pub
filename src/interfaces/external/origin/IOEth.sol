// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOEth {
    function rebasingCreditsPerToken() external view returns (uint256);
}
