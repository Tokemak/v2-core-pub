// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

//slither-disable-next-line name-reused
interface ICurvePool {
    function coins(uint256 i) external view returns (address);
}
