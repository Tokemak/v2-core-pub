// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract RootPriceOracleMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockRootPriceOraclePrices(IRootPriceOracle rootPriceOracle, address token, uint256 price) internal {
        _mockRootPriceOracleGetPriceInEth(rootPriceOracle, token, price);
        //_mockRootPriceOracleGetMinMaxPriceInEth(rootPriceOracle, token, minPrice, maxPrice);
    }

    function _mockRootPriceOracleGetPriceInEth(
        IRootPriceOracle rootPriceOracle,
        address token,
        uint256 price
    ) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    // function _mockRootPriceOracleGetMinMaxPriceInEth(
    //     IRootPriceOracle rootPriceOracle,
    //     address token,
    //     uint256 minPrice,
    //     uint256 maxPrice
    // ) internal {
    //     vm.mockCall(
    //         address(rootPriceOracle),
    //         abi.encodeWithSelector(IRootPriceOracle.getMinMaxPriceInEth.selector, token),
    //         abi.encode([minPrice, maxPrice])
    //     );
    // }
}
