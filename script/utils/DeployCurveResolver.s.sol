// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count,no-console

import { BaseScript } from "script/BaseScript.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { Systems } from "../utils/Constants.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

contract DeployCurveResolver is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast();

        CurveResolverMainnet resolver = new CurveResolverMainnet(ICurveMetaRegistry(constants.ext.curveMetaRegistry));
        SystemRegistry(address(systemRegistry)).setCurveResolver(address(resolver));

        vm.stopBroadcast();
    }
}
