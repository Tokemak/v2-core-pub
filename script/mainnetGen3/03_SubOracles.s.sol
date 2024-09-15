// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";

import { EethOracle } from "src/oracles/providers/EethOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { BalancerGyroscopeEthOracle } from "src/oracles/providers/BalancerGyroscopeEthOracle.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

contract SubOracles is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        WstETHEthOracle wstEthOracle = new WstETHEthOracle(constants.sys.systemRegistry, constants.tokens.wstEth);
        console.log("wstETH Oracle: ", address(wstEthOracle));

        EethOracle eEthOracle = new EethOracle(constants.sys.systemRegistry, constants.tokens.weEth);
        console.log("eETH Oracle: ", address(eEthOracle));

        EthPeggedOracle ethPegOracle = new EthPeggedOracle(constants.sys.systemRegistry);
        console.log("ETH Pegged Oracle: ", address(ethPegOracle));

        ChainlinkOracle chainlinkOracle = new ChainlinkOracle(constants.sys.systemRegistry);
        console.log("Chainlink Oracle: ", address(chainlinkOracle));

        CurveV1StableEthOracle curveV1Oracle =
            new CurveV1StableEthOracle(constants.sys.systemRegistry, constants.sys.curveResolver);
        console.log("Curve V1 Oracle: ", address(curveV1Oracle));

        CurveV2CryptoEthOracle curveV2Oracle =
            new CurveV2CryptoEthOracle(constants.sys.systemRegistry, constants.sys.curveResolver);
        console.log("Curve V2 Oracle: ", address(curveV2Oracle));

        BalancerLPMetaStableEthOracle balancerMetaOracle =
            new BalancerLPMetaStableEthOracle(constants.sys.systemRegistry, IBalancerVault(constants.ext.balancerVault));
        console.log("Balancer Meta Oracle: ", address(balancerMetaOracle));

        BalancerGyroscopeEthOracle balancerGyroOracle =
            new BalancerGyroscopeEthOracle(constants.sys.systemRegistry, IBalancerVault(constants.ext.balancerVault));
        console.log("Balancer Gyro Oracle: ", address(balancerGyroOracle));

        BalancerLPComposableStableEthOracle balancerCompOracle = new BalancerLPComposableStableEthOracle(
            constants.sys.systemRegistry, IBalancerVault(constants.ext.balancerVault)
        );
        console.log("Balancer Composable Oracle: ", address(balancerCompOracle));

        RedstoneOracle redstoneOracle = new RedstoneOracle(constants.sys.systemRegistry);
        console.log("Redstone Oracle: ", address(redstoneOracle));

        CustomSetOracle customSetOracle = new CustomSetOracle(constants.sys.systemRegistry, 1 days);
        console.log("Custom Set Oracle: ", address(customSetOracle));

        vm.stopBroadcast();
    }
}
