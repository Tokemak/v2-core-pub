// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/SystemComponent.sol";

/**
 * @notice This contract is a streamlined implementation of IPriceOracle.
 *  It's designed for tests that are agnostic to the type of price oracle being used.
 */
contract TestPriceOracle is SystemComponent, IPriceOracle {
    mapping(address => uint256) public priceInEth;

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "price";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external view returns (uint256) {
        return priceInEth[token];
    }

    /// @dev Use this function to manually set the price of a token in ETH
    /// @notice Sets the price of a token in ETH
    function setPriceInEth(address token, uint256 price) external {
        priceInEth[token] = price;
    }
}
