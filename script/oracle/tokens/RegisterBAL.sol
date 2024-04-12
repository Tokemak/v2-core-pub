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

contract RegisterBAL is BaseScript {
    address public constant BAL_MAINNET = 0xba100000625a3754423978a60c9317c58a424e3D;
    address public constant BAL_CL_FEED_MAINNET = 0xC1438AA3823A6Ba0C159CfA8D98dF5A994bA120b;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        // Deploy and set a new RootPriceOracle
        RootPriceOracle rootPriceOracle = RootPriceOracle(address(systemRegistry.rootPriceOracle()));
        ChainlinkOracle chainlinkOracle = ChainlinkOracle(constants.sys.subOracles.chainlink);

        // chainlinkOracle.registerOracle(
        //     BAL_MAINNET, IAggregatorV3Interface(BAL_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24
        // hours
        // );

        // New interfaces are different than whats currently deployed
        (bool success,) = address(chainlinkOracle).call(
            abi.encodeWithSignature(
                "registerChainlinkOracle(address,address,uint8,uint32)",
                BAL_MAINNET,
                IAggregatorV3Interface(BAL_CL_FEED_MAINNET),
                BaseOracleDenominations.Denomination.ETH,
                24 hours
            )
        );
        if (!success) {
            revert("Registration Failed");
        }

        _registerMapping(rootPriceOracle, chainlinkOracle, BAL_MAINNET, true);

        console.log("Queried Price: ", rootPriceOracle.getPriceInEth(BAL_MAINNET));

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
