// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
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

// solhint-disable state-visibility,no-console

contract CurveOracleBase is BaseScript {
    address constant STETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CBETH_MAINNET = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant WETH9_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant CRV_MAINNET = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant CVX_MAINNET = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant LDO_MAINNET = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address constant BADGER_MAINNET = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;
    address constant SUSD_MAINNET = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address constant WBTC_MAINNET = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant FRAX_MAINNET = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));

    // Mainnet Chainlink feed addresses
    address constant RETH_CL_FEED_MAINNET = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant USDC_CL_FEED_MAINNET = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address constant USDT_CL_FEED_MAINNET = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;
    address constant FRAX_CL_FEED_MAINNET = 0x14d04Fff8D21bd62987a5cE9ce543d2F1edF5D3E;
    address constant DAI_CL_FEED_MAINNET = 0x773616E4d11A78F511299002da57A0a94577F1f4;
    address constant SUSD_CL_FEED_MAINNET = 0x8e0b7e6062272B5eF4524250bFFF8e5Bd3497757;
    address constant CRV_CL_FEED_MAINNET = 0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e;
    address constant CVX_CL_FEED_MAINNET = 0xC9CbF687f43176B302F03f5e58470b77D07c61c6;

    address constant ETH_CL_FEED_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CBETH_CL_FEED_MAINNET = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant STETH_CL_FEED_MAINNET = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant LDO_CL_FEED_MAINNET = 0x4e844125952D32AcdF339BE976c98E22F6F318dB;
    address constant USDP_CL_FEED_MAINNET = 0x3a08ebBaB125224b7b6474384Ee39fBb247D2200;
    address constant TUSD_CL_FEED_MAINNET = 0x3886BA987236181D98F2401c507Fb8BeA7871dF2;
    address constant BADGER_CL_FEED_MAINNET = 0x58921Ac140522867bf50b9E009599Da0CA4A2379;
    address constant BTC_CL_FEED_MAINNET = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address constant USDP_MAINNET = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address constant TUSD_MAINNET = 0x0000000000085d4780B73119b644AE5ecd22b376;

    RootPriceOracle public rootPriceOracle;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        ICurveResolver curveResolver = ICurveResolver(systemRegistry.curveResolver());

        // Deploy and set a new RootPriceOracle
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        // Create all oracles
        WstETHEthOracle wstEthOracle = new WstETHEthOracle(systemRegistry, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        EthPeggedOracle ethPegOracle = new EthPeggedOracle(systemRegistry);
        ChainlinkOracle chainlinkOracle = new ChainlinkOracle(systemRegistry);
        CurveV1StableEthOracle curveV1Oracle = new CurveV1StableEthOracle(systemRegistry, curveResolver);
        CurveV2CryptoEthOracle curveV2Oracle = new CurveV2CryptoEthOracle(systemRegistry, curveResolver);
        BalancerLPMetaStableEthOracle balancerMetaOracle = new BalancerLPMetaStableEthOracle(
            systemRegistry, IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8)
        );

        // Register base tokens
        _registerMapping(chainlinkOracle, STETH_MAINNET, true);
        _registerMapping(wstEthOracle, WSTETH_MAINNET, true);
        _registerMapping(ethPegOracle, WETH9_ADDRESS, true);
        _registerMapping(ethPegOracle, CURVE_ETH, true);

        // Register incentive tokens
        _registerMapping(chainlinkOracle, CRV_MAINNET, true);
        _registerMapping(chainlinkOracle, CVX_MAINNET, true);
        _registerMapping(chainlinkOracle, LDO_MAINNET, true);

        // Register Balancer and Curve oracles
        _registerBalancerMeta(balancerMetaOracle);
        _registerCurveSet2(curveV2Oracle);
        _registerCurveSet1(curveV1Oracle);

        rootPriceOracle.setSafeSpotPriceThreshold(RETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WETH9_ADDRESS, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CURVE_ETH, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CBETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WSTETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(STETH_MAINNET, 200);

        _registerChainlinkOracles(chainlinkOracle);

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

    function _registerPoolMapping(ISpotPriceOracle oracle, address pool, bool replace) internal {
        ISpotPriceOracle existingPoolMappings = rootPriceOracle.poolMappings(pool);
        if (address(existingPoolMappings) == address(0)) {
            rootPriceOracle.registerPoolMapping(pool, oracle);
        } else {
            if (replace) {
                rootPriceOracle.replacePoolMapping(pool, existingPoolMappings, oracle);
            } else {
                console.log("pool %s is already registed", pool);
            }
        }
    }

    function _registerBalancerMeta(BalancerLPMetaStableEthOracle balMetaOracle) internal {
        // Register balancer pools
        address balancerWstEthWethPool = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        address balancerWstEthCbEthPool = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        address balancerRethWethPool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

        _registerPoolMapping(balMetaOracle, balancerWstEthWethPool, true);
        _registerPoolMapping(balMetaOracle, balancerWstEthCbEthPool, true);
        _registerPoolMapping(balMetaOracle, balancerRethWethPool, true);
    }

    function _registerCurveSet2(CurveV2CryptoEthOracle curveV2Oracle) internal {
        address curveV2RethEthPool = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
        address curveV2RethEthLpToken = 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C;

        curveV2Oracle.registerPool(curveV2RethEthPool, curveV2RethEthLpToken, true);
        _registerPoolMapping(curveV2Oracle, curveV2RethEthPool, true);

        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;

        curveV2Oracle.registerPool(curveV2cbEthEthPool, curveV2cbEthEthLpToken, true);
        _registerPoolMapping(curveV2Oracle, curveV2cbEthEthPool, true);
    }

    function _registerCurveSet1(CurveV1StableEthOracle curveV1Oracle) internal {
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;

        curveV1Oracle.registerPool(curveStEthOriginalPool, curveStEthOriginalLpToken, true);
        _registerPoolMapping(curveV1Oracle, curveStEthOriginalPool, true);

        address curveStEthConcentratedPool = 0x828b154032950C8ff7CF8085D841723Db2696056;
        address curveStEthConcentratedLpToken = 0x828b154032950C8ff7CF8085D841723Db2696056;

        curveV1Oracle.registerPool(curveStEthConcentratedPool, curveStEthConcentratedLpToken, false);
        _registerPoolMapping(curveV1Oracle, curveStEthConcentratedPool, true);

        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        curveV1Oracle.registerPool(curveStEthNgPool, curveStEthNgLpToken, false);
        _registerPoolMapping(curveV1Oracle, curveStEthNgPool, true);

        address curveRethWstethPool = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveRethWstethLpToken = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;

        curveV1Oracle.registerPool(curveRethWstethPool, curveRethWstethLpToken, false);
        _registerPoolMapping(curveV1Oracle, curveRethWstethPool, true);
    }

    function _registerChainlinkOracles(ChainlinkOracle chainlinkOracle) internal {
        // Chainlink setup
        chainlinkOracle.registerOracle(
            STETH_MAINNET,
            IAggregatorV3Interface(STETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            CRV_MAINNET, IAggregatorV3Interface(CRV_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            CVX_MAINNET, IAggregatorV3Interface(CVX_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            ETH_IN_USD, IAggregatorV3Interface(ETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 0
        );

        // Following might not be needed for guarded launch
        chainlinkOracle.registerOracle(
            DAI_MAINNET, IAggregatorV3Interface(DAI_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            USDC_MAINNET,
            IAggregatorV3Interface(USDC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            USDT_MAINNET,
            IAggregatorV3Interface(USDT_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        chainlinkOracle.registerOracle(
            FRAX_MAINNET,
            IAggregatorV3Interface(FRAX_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            USDP_MAINNET,
            IAggregatorV3Interface(USDP_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            TUSD_MAINNET,
            IAggregatorV3Interface(TUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            SUSD_MAINNET,
            IAggregatorV3Interface(SUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        chainlinkOracle.registerOracle(
            LDO_MAINNET, IAggregatorV3Interface(LDO_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            BADGER_MAINNET,
            IAggregatorV3Interface(BADGER_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            2 hours
        );
        chainlinkOracle.registerOracle(
            WBTC_MAINNET,
            IAggregatorV3Interface(BTC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
    }
}
