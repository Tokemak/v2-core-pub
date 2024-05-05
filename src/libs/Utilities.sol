// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

library Utilities {
    /**
     * @notice We subtract decimals to help us not impact a pool when making swaps, pricing, etc.
     */
    function getScaledDownDecimals(IERC20Metadata token) public view returns (uint256) {
        return token.decimals() - getScaleDownFactor(token);
    }

    /**
     * @notice Gets a subtraction factor based on decimals size.
     * @dev We're making this factor dynamic based on the decimals of the token.
     */
    function getScaleDownFactor(IERC20Metadata token) public view returns (uint256 scaleDownFactor) {
        uint256 decimals = token.decimals();

        if (decimals <= 2) {
            scaleDownFactor = 0;
        }
        if (decimals > 2) {
            scaleDownFactor = 1;
        }
        if (decimals == 6) {
            scaleDownFactor = 2;
        }
        if (decimals > 6) {
            scaleDownFactor = 3;
        }
        if (decimals >= 18) {
            scaleDownFactor = 4;
        }
    }
}
