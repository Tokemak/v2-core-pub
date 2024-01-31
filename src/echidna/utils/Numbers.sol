// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

contract Numbers {
    /// @notice Tweak the value up or down by the provided pct
    function tweak(uint256 value, int8 pct) internal pure returns (uint256 output) {
        output = value;

        if (pct < 0) {
            output -= output * uint256(int256(pct) * -1) / 128;
        } else if (pct > 0) {
            output += output * uint256(uint8(pct)) / 127;
        }
    }
}
