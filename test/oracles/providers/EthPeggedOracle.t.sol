// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";

contract EthPeggedOracleTests is Test {
    ISystemRegistry private _systemRegistry;
    EthPeggedOracle private _oracle;

    function setUp() public {
        _systemRegistry = ISystemRegistry(vm.addr(324));
        _oracle = new EthPeggedOracle(_systemRegistry);
    }

    function testBasicPrice(address token) public {
        uint256 price = _oracle.getPriceInEth(token);

        assertEq(price, 1e18);
    }
}
