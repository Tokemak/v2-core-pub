// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { console } from "forge-std/console.sol";
import { Constants } from "../utils/Constants.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { RootPriceOracle, IRootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract Oracle {
    struct ChainlinkOracleSetup {
        address tokenAddress;
        address feedAddress;
        BaseOracleDenominations.Denomination denomination;
        uint32 heartbeat;
        uint256 safePriceThreshold;
    }

    struct RedstoneOracleSetup {
        address tokenAddress;
        address feedAddress;
        BaseOracleDenominations.Denomination denomination;
        uint32 heartbeat;
        uint256 safePriceThreshold;
    }

    function _setupRedstoneOracle(Constants.Values memory constants, RedstoneOracleSetup memory args) internal {
        constants.sys.subOracles.redStone.registerOracle(
            args.tokenAddress, IAggregatorV3Interface(args.feedAddress), args.denomination, args.heartbeat
        );

        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.redStone, args.tokenAddress, true);

        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(args.tokenAddress, args.safePriceThreshold);
    }

    function _setupChainlinkOracle(Constants.Values memory constants, ChainlinkOracleSetup memory args) internal {
        constants.sys.subOracles.chainlink.registerOracle(
            args.tokenAddress, IAggregatorV3Interface(args.feedAddress), args.denomination, args.heartbeat
        );

        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.chainlink, args.tokenAddress, true);

        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(args.tokenAddress, args.safePriceThreshold);
    }

    function _registerMapping(
        IRootPriceOracle rootPriceOracle,
        IPriceOracle oracle,
        address token,
        bool replace
    ) internal {
        IPriceOracle existingRootPriceOracle = RootPriceOracle(address(rootPriceOracle)).tokenMappings(token);
        if (address(existingRootPriceOracle) == address(0)) {
            RootPriceOracle(address(rootPriceOracle)).registerMapping(token, oracle);
        } else {
            if (replace) {
                RootPriceOracle(address(rootPriceOracle)).replaceMapping(token, existingRootPriceOracle, oracle);
            } else {
                console.log("token %s is already registered", token);
            }
        }
    }

    function _registerPoolMapping(
        IRootPriceOracle rootPriceOracle,
        ISpotPriceOracle oracle,
        address pool,
        bool replace
    ) internal {
        ISpotPriceOracle existingPoolMappings = RootPriceOracle(address(rootPriceOracle)).poolMappings(pool);
        if (address(existingPoolMappings) == address(0)) {
            RootPriceOracle(address(rootPriceOracle)).registerPoolMapping(pool, oracle);
        } else {
            if (replace) {
                RootPriceOracle(address(rootPriceOracle)).replacePoolMapping(pool, existingPoolMappings, oracle);
            } else {
                console.log("pool %s is already registered", pool);
            }
        }
    }
}
