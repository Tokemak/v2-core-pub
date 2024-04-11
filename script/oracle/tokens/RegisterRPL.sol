// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";

// solhint-disable state-visibility,no-console,avoid-low-level-calls

contract RegisterRPL is BaseScript {
    address public constant RPL_MAINNET = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;
    address public constant RPL_CL_FEED_MAINNET = 0x4E155eD98aFE9034b7A5962f6C84c86d869daA9d;
    address public constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));
    address constant ETH_CL_FEED_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        // Deploy and set a new RootPriceOracle
        RootPriceOracle rootPriceOracle = RootPriceOracle(address(systemRegistry.rootPriceOracle()));
        ChainlinkOracle chainlinkOracle = ChainlinkOracle(constants.sys.subOracles.chainlink);

        // chainlinkOracle.registerOracle(
        //     RPL_MAINNET, IAggregatorV3Interface(RPL_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 24
        // hours
        // );

        // New interfaces are different than whats currently deployed
        (bool success,) = address(chainlinkOracle).call(
            abi.encodeWithSignature(
                "registerChainlinkOracle(address,address,uint8,uint32)",
                RPL_MAINNET,
                IAggregatorV3Interface(RPL_CL_FEED_MAINNET),
                BaseOracleDenominations.Denomination.USD,
                24 hours
            )
        );
        if (!success) {
            revert("Registration Failed");
        }

        _registerMapping(rootPriceOracle, chainlinkOracle, RPL_MAINNET, true);

        // ETH to USD isn't registered yet
        // chainlinkOracle.registerOracle(
        //     ETH_IN_USD, IAggregatorV3Interface(ETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 2
        // hours
        // );
        (bool usdSuccess,) = address(chainlinkOracle).call(
            abi.encodeWithSignature(
                "registerChainlinkOracle(address,address,uint8,uint32)",
                ETH_IN_USD,
                IAggregatorV3Interface(ETH_CL_FEED_MAINNET),
                BaseOracleDenominations.Denomination.USD,
                2 hours
            )
        );
        if (!usdSuccess) {
            revert("usd fail");
        }
        _registerMapping(rootPriceOracle, chainlinkOracle, ETH_IN_USD, true);

        console.log("Queried Price: ", rootPriceOracle.getPriceInEth(RPL_MAINNET));

        vm.stopBroadcast();
    }

    function _registerMapping(
        RootPriceOracle rootPriceOracle,
        IPriceOracle oracle,
        address token,
        bool replace
    ) internal {
        IPriceOracle existingRootPriceOracle = rootPriceOracle.tokenMappings(token);
        if (address(existingRootPriceOracle) == address(0)) {
            rootPriceOracle.registerMapping(token, oracle);
            console.log("Token %s registered", token);
        } else {
            if (replace) {
                rootPriceOracle.replaceMapping(token, existingRootPriceOracle, oracle);
                console.log("Token %s re-registered", token);
            } else {
                console.log("Token %s is already registered", token);
            }
        }
    }
}
