// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems } from "script/utils/Constants.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";

import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

import { Roles } from "src/libs/Roles.sol";

import { Systems, Constants } from "../utils/Constants.sol";
import { Oracle } from "script/core/Oracle.sol";

// solhint-disable state-visibility,no-console

contract OracleSetup is Script, Oracle {
    address constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));

    // Mainnet Chainlink feed addresses
    address constant STETH_CL_FEED_MAINNET = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant RETH_CL_FEED_MAINNET = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant CBETH_CL_FEED_MAINNET = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant CRV_CL_FEED_MAINNET = 0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e;
    address constant CVX_CL_FEED_MAINNET = 0xC9CbF687f43176B302F03f5e58470b77D07c61c6;
    address constant LDO_CL_FEED_MAINNET = 0x4e844125952D32AcdF339BE976c98E22F6F318dB;
    address constant ETH_CL_FEED_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant RPL_CL_FEED_MAINNET = 0x4E155eD98aFE9034b7A5962f6C84c86d869daA9d;
    address constant BAL_CL_FEED_MAINNET = 0xC1438AA3823A6Ba0C159CfA8D98dF5A994bA120b;

    // Mainnet Redstone feed address
    address constant REDSTONE_OSETH_PRICE_FEED = 0x66ac817f997Efd114EDFcccdce99F3268557B32C;
    address constant REDSTONE_SWETH_PRICE_FEED = 0x061bB36F8b67bB922937C102092498dcF4619F86;

    SystemRegistry public systemRegistry;
    RootPriceOracle public rootPriceOracle;

    RedstoneOracle redstoneOracle;
    CustomSetOracle customSetOracle;

    Constants.Values values;

    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        values = Constants.get(Systems.LST_GEN2_MAINNET);
        systemRegistry = values.sys.systemRegistry;
        rootPriceOracle = values.sys.rootPriceOracle;

        // Create all oracles
        WstETHEthOracle wstEthOracle = new WstETHEthOracle(systemRegistry, values.tokens.wstEth);
        console.log("wstEthOracle: ", address(wstEthOracle));

        EthPeggedOracle ethPegOracle = new EthPeggedOracle(systemRegistry);
        console.log("ethPegOracle: ", address(ethPegOracle));

        ChainlinkOracle chainlinkOracle = new ChainlinkOracle(systemRegistry);
        console.log("chainlinkOracle: ", address(chainlinkOracle));

        CurveV1StableEthOracle curveV1Oracle = new CurveV1StableEthOracle(systemRegistry, values.sys.curveResolver);
        console.log("curveV1Oracle: ", address(curveV1Oracle));

        CurveV2CryptoEthOracle curveV2Oracle = new CurveV2CryptoEthOracle(systemRegistry, values.sys.curveResolver);
        console.log("curveV2Oracle: ", address(curveV2Oracle));

        BalancerLPMetaStableEthOracle balancerMetaOracle =
            new BalancerLPMetaStableEthOracle(systemRegistry, IBalancerVault(values.ext.balancerVault));
        console.log("balancerMetaOracle: ", address(balancerMetaOracle));

        redstoneOracle = new RedstoneOracle(systemRegistry);
        console.log("redstoneOracle: ", address(redstoneOracle));

        customSetOracle = new CustomSetOracle(systemRegistry, 1 days);
        console.log("customSetOracle: ", address(customSetOracle));

        values.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        // Register base tokens
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.cbEth, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.rEth, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.stEth, true);
        _registerMapping(rootPriceOracle, wstEthOracle, values.tokens.wstEth, true);
        _registerMapping(rootPriceOracle, ethPegOracle, values.tokens.weth, true);
        _registerMapping(rootPriceOracle, ethPegOracle, values.tokens.curveEth, true);

        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.crv, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.cvx, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.ldo, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.rpl, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, values.tokens.bal, true);
        _registerMapping(rootPriceOracle, chainlinkOracle, ETH_IN_USD, true);

        // Register Balancer and Curve oracles
        _registerBalancerMeta(balancerMetaOracle);
        _registerCurveSet2(curveV2Oracle);
        _registerCurveSet1(curveV1Oracle);

        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.rEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.weth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.curveEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.cbEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.wstEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.stEth, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(values.tokens.osEth, 200);

        _registerChainlinkOracles(chainlinkOracle);

        _registerCustomSet();

        values.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }

    function _registerCustomSet() internal {
        address[] memory tokens = new address[](2);
        uint256[] memory maxAges = new uint256[](2);

        tokens[0] = values.tokens.aura;
        maxAges[0] = 1 days;

        tokens[1] = values.tokens.swise;
        maxAges[1] = 1 days;

        customSetOracle.registerTokens(tokens, maxAges);
        for (uint256 i = 0; i < tokens.length; ++i) {
            rootPriceOracle.registerMapping(tokens[i], customSetOracle);
        }
    }

    function _registerBalancerMeta(BalancerLPMetaStableEthOracle balMetaOracle) internal {
        // Register balancer pools
        address balancerWstEthWethPool = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        address balancerRethWethPool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

        _registerPoolMapping(rootPriceOracle, balMetaOracle, balancerWstEthWethPool, true);
        _registerPoolMapping(rootPriceOracle, balMetaOracle, balancerRethWethPool, true);
    }

    function _registerCurveSet2(CurveV2CryptoEthOracle curveV2Oracle) internal {
        address curveV2RethEthPool = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
        address curveV2RethEthLpToken = 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C;

        curveV2Oracle.registerPool(curveV2RethEthPool, curveV2RethEthLpToken);
        _registerPoolMapping(rootPriceOracle, curveV2Oracle, curveV2RethEthPool, true);

        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;

        curveV2Oracle.registerPool(curveV2cbEthEthPool, curveV2cbEthEthLpToken);
        _registerPoolMapping(rootPriceOracle, curveV2Oracle, curveV2cbEthEthPool, true);
    }

    function _registerCurveSet1(CurveV1StableEthOracle curveV1Oracle) internal {
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;

        curveV1Oracle.registerPool(curveStEthOriginalPool, curveStEthOriginalLpToken);
        _registerPoolMapping(rootPriceOracle, curveV1Oracle, curveStEthOriginalPool, true);

        address curveStEthConcentratedPool = 0x828b154032950C8ff7CF8085D841723Db2696056;
        address curveStEthConcentratedLpToken = 0x828b154032950C8ff7CF8085D841723Db2696056;

        curveV1Oracle.registerPool(curveStEthConcentratedPool, curveStEthConcentratedLpToken);
        _registerPoolMapping(rootPriceOracle, curveV1Oracle, curveStEthConcentratedPool, true);

        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        curveV1Oracle.registerPool(curveStEthNgPool, curveStEthNgLpToken);
        _registerPoolMapping(rootPriceOracle, curveV1Oracle, curveStEthNgPool, true);

        address curveRethWstethPool = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveRethWstethLpToken = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;

        curveV1Oracle.registerPool(curveRethWstethPool, curveRethWstethLpToken);
        _registerPoolMapping(rootPriceOracle, curveV1Oracle, curveRethWstethPool, true);

        address curveOsEthRethPool = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        address curveOsEthRethLpToken = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;

        curveV1Oracle.registerPool(curveOsEthRethPool, curveOsEthRethLpToken);
        _registerPoolMapping(rootPriceOracle, curveV1Oracle, curveOsEthRethPool, true);
    }

    function _registerRedstoneOracles(RedstoneOracle oracle) internal {
        oracle.registerOracle(
            values.tokens.osEth,
            IAggregatorV3Interface(REDSTONE_OSETH_PRICE_FEED),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        _registerMapping(rootPriceOracle, oracle, values.tokens.osEth, true);

        oracle.registerOracle(
            values.tokens.swEth,
            IAggregatorV3Interface(REDSTONE_SWETH_PRICE_FEED),
            BaseOracleDenominations.Denomination.ETH,
            6 hours
        );
        _registerMapping(rootPriceOracle, oracle, values.tokens.swEth, true);
    }

    function _registerChainlinkOracles(ChainlinkOracle chainlinkOracle) internal {
        // Chainlink setup
        chainlinkOracle.registerOracle(
            values.tokens.rEth,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.cbEth,
            IAggregatorV3Interface(CBETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.stEth,
            IAggregatorV3Interface(STETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.crv,
            IAggregatorV3Interface(CRV_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            values.tokens.cvx,
            IAggregatorV3Interface(CVX_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            ETH_IN_USD, IAggregatorV3Interface(ETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 2 hours
        );

        chainlinkOracle.registerOracle(
            values.tokens.ldo,
            IAggregatorV3Interface(LDO_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        chainlinkOracle.registerOracle(
            values.tokens.rpl,
            IAggregatorV3Interface(RPL_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.USD,
            24 hours
        );

        chainlinkOracle.registerOracle(
            values.tokens.bal,
            IAggregatorV3Interface(BAL_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
    }
}
