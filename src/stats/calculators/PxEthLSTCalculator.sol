// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract PxEthLSTCalculator is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public pure override returns (uint256) {
        return 1 ether;
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsBacking() public pure override returns (bool) {
        return true;
    }
}
