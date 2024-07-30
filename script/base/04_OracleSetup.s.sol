// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";

import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

import { Roles } from "src/libs/Roles.sol";

import { Systems, Constants } from "../utils/Constants.sol";

// solhint-disable state-visibility,no-console

contract CurveOracleBase is Script {
    address constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));

    address constant AERO_USD_CL_FEED_BASE = 0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0;
    address constant CBETH_ETH_CL_FEED_BASE = 0x806b4Ac04501c29769051e42783cF04dCE41440b;
    address constant ETH_USD_CL_FEED_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant RETH_ETH_CL_FEED_BASE = 0xf397bF97280B488cA19ee3093E81C0a77F02e9a5;
    address constant WSTETH_ETH_CL_FEED_BASE = 0xa669E5272E60f78299F4824495cE01a3923f4380;
    address constant EZETH_ETH_CL_FEED_BASE = 0x960BDD1dFD20d7c98fa482D793C3dedD73A113a3;

    SystemRegistry public systemRegistry;
    RootPriceOracle public rootPriceOracle;

    CustomSetOracle customSetOracle;

    Constants.Values values;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values = Constants.get(Systems.LST_GEN1_BASE);
        systemRegistry = values.sys.systemRegistry;
        rootPriceOracle = values.sys.rootPriceOracle;

        // Create all oracles

        EthPeggedOracle ethPegOracle = new EthPeggedOracle(systemRegistry);
        console.log("ethPegOracle: ", address(ethPegOracle));

        ChainlinkOracle chainlinkOracle = new ChainlinkOracle(systemRegistry);
        console.log("chainlinkOracle: ", address(chainlinkOracle));

        BalancerLPComposableStableEthOracle balancerCompOracle =
            new BalancerLPComposableStableEthOracle(systemRegistry, IBalancerVault(values.ext.balancerVault));
        console.log("balancerCompOracle: ", address(balancerCompOracle));

        customSetOracle = new CustomSetOracle(systemRegistry, 1 days);
        console.log("customSetOracle: ", address(customSetOracle));

        values.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        // Register base tokens
        _registerMapping(chainlinkOracle, values.tokens.aero, true);
        _registerMapping(chainlinkOracle, values.tokens.cbEth, true);
        _registerMapping(chainlinkOracle, ETH_IN_USD, true);
        _registerMapping(chainlinkOracle, values.tokens.rEth, true);
        _registerMapping(chainlinkOracle, values.tokens.wstEth, true);
        _registerMapping(chainlinkOracle, values.tokens.ezEth, true);

        _registerMapping(ethPegOracle, values.tokens.weth, true);
        _registerMapping(ethPegOracle, values.tokens.curveEth, true);

        // Register Balancer and Curve oracles
        _registerBalancerMeta(balancerCompOracle);

        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.aero, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.cbEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.curveEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.rEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.wstEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.ezEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.weth, 200);

        _registerChainlinkOracles(chainlinkOracle);

        _registerCustomSet();

        values.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();

        console.log("wstETH Price", rootPriceOracle.getPriceInEth(values.tokens.wstEth));
        console.log("aero Price", rootPriceOracle.getPriceInEth(values.tokens.aero));
        console.log("rEth Price", rootPriceOracle.getPriceInEth(values.tokens.rEth));
        console.log("ezEth Price", rootPriceOracle.getPriceInEth(values.tokens.ezEth));
    }

    function _registerCustomSet() internal {
        address[] memory tokens = new address[](2);
        uint256[] memory maxAges = new uint256[](2);

        tokens[0] = values.tokens.aura;
        maxAges[0] = 1 days;

        tokens[1] = values.tokens.bal;
        maxAges[1] = 1 days;

        customSetOracle.registerTokens(tokens, maxAges);
        for (uint256 i = 0; i < tokens.length; ++i) {
            rootPriceOracle.registerMapping(tokens[i], customSetOracle);
        }
    }

    function _registerMapping(IPriceOracle oracle, address lpToken, bool replace) internal {
        IPriceOracle existingRootPriceOracle = rootPriceOracle.tokenMappings(lpToken);
        if (address(existingRootPriceOracle) == address(0)) {
            rootPriceOracle.registerMapping(lpToken, oracle);
        } else {
            if (replace) {
                rootPriceOracle.replaceMapping(lpToken, existingRootPriceOracle, oracle);
            } else {
                console.log("lpToken %s is already registered", lpToken);
            }
        }
    }

    function _registerPoolMapping(ISpotPriceOracle oracle, address pool, bool replace) internal {
        ISpotPriceOracle existingPoolMappings = rootPriceOracle.poolMappings(pool);
        if (address(existingPoolMappings) == address(0)) {
            rootPriceOracle.registerPoolMapping(pool, oracle);
        } else {
            if (replace) {
                rootPriceOracle.replacePoolMapping(pool, existingPoolMappings, oracle);
            } else {
                console.log("pool %s is already registered", pool);
            }
        }
    }

    function _registerBalancerMeta(BalancerLPComposableStableEthOracle balCompOracle) internal {
        // Register balancer pools
        address balancerWethRethCompStable = 0xC771c1a5905420DAEc317b154EB13e4198BA97D0;
        address balancerCbEthWethCompStable = 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6;

        _registerPoolMapping(balCompOracle, balancerWethRethCompStable, true);
        _registerPoolMapping(balCompOracle, balancerCbEthWethCompStable, true);
    }

    function _registerChainlinkOracles(ChainlinkOracle chainlinkOracle) internal {
        // Chainlink setup
        chainlinkOracle.registerOracle(
            values.tokens.aero,
            IAggregatorV3Interface(AERO_USD_CL_FEED_BASE),
            BaseOracleDenominations.Denomination.USD,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.cbEth,
            IAggregatorV3Interface(CBETH_ETH_CL_FEED_BASE),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            ETH_IN_USD, IAggregatorV3Interface(ETH_USD_CL_FEED_BASE), BaseOracleDenominations.Denomination.USD, 24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.rEth,
            IAggregatorV3Interface(RETH_ETH_CL_FEED_BASE),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.ezEth,
            IAggregatorV3Interface(EZETH_ETH_CL_FEED_BASE),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.wstEth,
            IAggregatorV3Interface(WSTETH_ETH_CL_FEED_BASE),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
    }
}
