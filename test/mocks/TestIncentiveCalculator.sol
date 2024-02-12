// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

contract TestIncentiveCalculator {
    address internal _lpToken;

    constructor(address lpToken) {
        _lpToken = lpToken;
    }

    function resolveLpToken() public view virtual returns (address lpToken) {
        return _lpToken;
    }
}
