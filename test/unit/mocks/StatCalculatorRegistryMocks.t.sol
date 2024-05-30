// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { Errors } from "src/utils/Errors.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";

contract StatCalculatorRegistryMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockStatCalcRegistryGetCalculator(
        IStatsCalculatorRegistry registry,
        bytes32 key,
        address calculator
    ) internal {
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IStatsCalculatorRegistry.getCalculator.selector, key),
            abi.encode(calculator)
        );
    }

    function _mockStatCalcRegistryGetCalculatorRevert(IStatsCalculatorRegistry registry, bytes32 key) internal {
        bytes memory customError = abi.encodeWithSelector(Errors.ZeroAddress.selector, "calcAddress");
        vm.mockCallRevert(
            address(registry), abi.encodeWithSelector(IStatsCalculatorRegistry.getCalculator.selector, key), customError
        );
    }
}
