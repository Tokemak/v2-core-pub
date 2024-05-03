// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { IswETH } from "src/interfaces/external/swell/IswETH.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract SwethLSTCalculator is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IswETH(lstTokenAddress).swETHToETHRate();
    }

    /// @inheritdoc LSTCalculatorBase
    function isRebasing() public pure override returns (bool) {
        return false;
    }
}
