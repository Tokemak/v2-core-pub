// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { IrswETH } from "src/interfaces/external/swell/IrswETH.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract RswethLRTCalculator is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IrswETH(lstTokenAddress).rswETHToETHRate();
    }

    /// @inheritdoc LSTCalculatorBase
    function isRebasing() public pure override returns (bool) {
        return false;
    }
}
