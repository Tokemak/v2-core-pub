// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Numbers } from "test/echidna/fuzz/utils/Numbers.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

/// @title Root oracle with no permissions and abilities to set and tweak prices
contract MockRootOracle is Numbers, IRootPriceOracle {
    address public getSystemRegistry;
    mapping(address => uint256) internal prices;

    mapping(address => int8) internal safeTweak;
    mapping(address => int8) internal spotTweak;
    mapping(address => int8) internal ceilingTweak;
    mapping(address => int8) internal floorTweak;

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

    function setSafeTweak(address token, int8 pct) public {
        if (pct < -20) {
            pct = -20;
        }
        if (pct > 20) {
            pct = 20;
        }
        safeTweak[token] = pct;
    }

    function setSpotTweak(address token, int8 pct) public {
        if (pct < -20) {
            pct = -20;
        }
        if (pct > 20) {
            pct = 20;
        }
        spotTweak[token] = pct;
    }

    function setCeilingTweak(address token, uint8 pct) public {
        if (pct > 100) {
            pct = 100;
        }

        ceilingTweak[token] = int8(pct);
    }

    function setFloorTweak(address token, uint8 pct) public {
        if (pct > 100) {
            pct = 100;
        }
        floorTweak[token] = int8(int8(pct) * int8(-1));
    }

    function getPriceInEth(address token) public view returns (uint256) {
        return prices[token];
    }

    function getSpotPriceInEth(address, address) external pure returns (uint256) {
        revert NotImplemented();
    }

    function getPriceInQuote(address, address) external pure returns (uint256) {
        revert NotImplemented();
    }

    function getFloorPrice(address lpToken, address, address) external view returns (uint256) {
        return tweak(prices[lpToken], floorTweak[lpToken]);
    }

    function getCeilingPrice(address lpToken, address, address) external view returns (uint256) {
        return tweak(prices[lpToken], ceilingTweak[lpToken]);
    }

    function getFloorCeilingPrice(
        address,
        address lpToken,
        address,
        bool ceiling
    ) external view returns (uint256 floorOrCeilingPerLpToken) {
        floorOrCeilingPerLpToken =
            ceiling ? tweak(prices[lpToken], ceilingTweak[lpToken]) : tweak(prices[lpToken], floorTweak[lpToken]);
    }

    function getRangePricesLP(address lpToken, address, address) external view returns (uint256, uint256, bool) {
        int8 safeTk = safeTweak[lpToken];
        int8 spotTk = spotTweak[lpToken];

        return (tweak(prices[lpToken], spotTk), tweak(prices[lpToken], safeTk), true);
    }
}
