// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

contract TestIncentiveCalculator {
    address internal _lpToken;
    address internal _poolAddress;

    function resolveLpToken() public view virtual returns (address lpToken) {
        return _lpToken;
    }

    function poolAddress() public view virtual returns (address) {
        return _poolAddress;
    }

    function setLpToken(address lpToken) public {
        _lpToken = lpToken;
    }

    function setPoolAddress(address poolAddress_) public {
        _poolAddress = poolAddress_;
    }
}
