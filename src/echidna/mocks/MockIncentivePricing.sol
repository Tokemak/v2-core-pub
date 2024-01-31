// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Numbers } from "src/echidna/utils/Numbers.sol";

/// @title Incentive pricing with no permissions and abilities to set and tweak prices
contract MockIncentivePricing is Numbers {
    uint256 private slowPrice;
    uint256 private fastPrice;

    function setSlowPrice(uint256 price) public {
        slowPrice = price;
    }

    function setFastPrice(uint256 price) public {
        fastPrice = price;
    }

    function tweakSlowPrice(int8 pct) external {
        slowPrice = tweak(slowPrice, pct);
    }

    function tweakFastPrice(int8 pct) external {
        fastPrice = tweak(fastPrice, pct);
    }

    function getPrice(address, uint40) public view returns (uint256 _fastPrice, uint256 _slowPrice) {
        _fastPrice = fastPrice;
        _slowPrice = slowPrice;
    }

    function getPriceOrZero(address token, uint40 staleCheck) external view returns (uint256 f, uint256 s) {
        (f, s) = getPrice(token, staleCheck);
    }
}
