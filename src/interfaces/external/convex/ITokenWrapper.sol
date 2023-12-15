// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITokenWrapper {
    function isInvalid() external view returns (bool);
    function token() external view returns (address);
}
