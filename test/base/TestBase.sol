// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Vm } from "forge-std/Vm.sol";

contract TestBase {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function newAddr(uint256 privateKey, string memory label) internal returns (address ret) {
        ret = vm.addr(privateKey);
        vm.label(ret, label);
    }
}
