// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IStaderOracle } from "src/interfaces/external/stader/IStaderOracle.sol";

interface IStaderConfig {
    function getStaderOracle() external view returns (IStaderOracle);
}
