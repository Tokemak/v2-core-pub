// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Numbers } from "src/echidna/utils/Numbers.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

// solhint-disable no-unused-vars

/// @title Root oracle with no permissions and abilities to set and tweak prices
contract MockRootOracle is Numbers, IRootPriceOracle {
    address public getSystemRegistry;
    mapping(address => uint256) internal prices;

    error NotImplemented();

    constructor(address _systemRegistry) {
        getSystemRegistry = _systemRegistry;
    }

    function setPrice(address token, uint256 price) public {
        prices[token] = price;
    }

    function tweakPrice(address token, int8 pct) public {
        prices[token] = tweak(prices[token], pct);
    }

    function getPriceInEth(address token) public view returns (uint256) {
        return prices[token];
    }

    function getSpotPriceInEth(address token, address pool) external returns (uint256) {
        revert NotImplemented();
    }

    function getPriceInQuote(address base, address quote) external returns (uint256 price) {
        revert NotImplemented();
    }

    function getRangePricesLP(
        address lpToken,
        address pool,
        address quoteToken
    ) external returns (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) {
        revert NotImplemented();
    }

    function getFloorCeilingPrice(
        address pool,
        address lptoken,
        address inQuote,
        bool ceiling
    ) external returns (uint256) {
        revert NotImplemented();
    }
}
