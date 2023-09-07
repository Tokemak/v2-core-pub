// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IRateProvider } from "script/interfaces/balancer/IRateProvider.sol";

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract MockRateProvider is IRateProvider, Ownable {
    uint256 public rate;
    address public token;

    constructor(address _token, uint256 _rate) {
        token = _token;
        rate = _rate;
    }

    function getRate() external view override returns (uint256) {
        return rate;
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }
}
