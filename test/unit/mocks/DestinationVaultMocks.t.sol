// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";

contract DestinationVaultMocks {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function _mockDestVaultRangePricesLP(
        address destVault,
        uint256 spotPrice,
        uint256 safePrice,
        bool isSpotSafe
    ) internal {
        vm.mockCall(
            destVault, abi.encodeWithSignature("getRangePricesLP()"), abi.encode(spotPrice, safePrice, isSpotSafe)
        );
    }

    function _mockDestVaultFloorPrice(address destVault, uint256 floorPrice) internal {
        vm.mockCall(destVault, abi.encodeWithSignature("getUnderlyerFloorPrice()"), abi.encode([floorPrice]));
    }

    function _mockDestVaultCeilingPrice(address destVault, uint256 ceilingPrice) internal {
        vm.mockCall(destVault, abi.encodeWithSignature("getUnderlyerCeilingPrice()"), abi.encode([ceilingPrice]));
    }
}
