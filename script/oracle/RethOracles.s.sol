// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Ops Ltd. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";

// solhint-disable state-visibility,no-console

contract CurveOracleBase is BaseScript {
    address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    RootPriceOracle rootPriceOracle;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        rootPriceOracle = RootPriceOracle(address(systemRegistry.rootPriceOracle()));

        _registerMapping(IPriceOracle(0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72), RETH_MAINNET, true);

        vm.stopBroadcast();
    }

    function _registerMapping(IPriceOracle oracle, address lpToken, bool replace) internal {
        IPriceOracle existingRootPriceOracle = rootPriceOracle.tokenMappings(lpToken);
        if (address(existingRootPriceOracle) == address(0)) {
            rootPriceOracle.registerMapping(lpToken, oracle);
        } else {
            if (replace) {
                rootPriceOracle.replaceMapping(lpToken, existingRootPriceOracle, oracle);
            } else {
                console.log("lpToken %s is already registed", lpToken);
            }
        }
    }
}
