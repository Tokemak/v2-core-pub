// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,state-visibility

import { console } from "forge-std/console.sol";

import { BaseScript, Systems } from "script/BaseScript.sol";

import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/interfaces/swapper/ISyncSwapper.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { console } from "forge-std/console.sol";

/// @dev Sets swap route for tokens on `SwapRouter.sol` contract.
contract Oralces is BaseScript {
    address constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    address constant STETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CBETH_MAINNET = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant STETH_CL_FEED_MAINNET = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant RETH_CL_FEED_MAINNET = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant CBETH_CL_FEED_MAINNET = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant WETH9_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));
        SystemRegistry _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);
        CurveResolverMainnet curveResolver =
            new CurveResolverMainnet(ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC));
        _systemRegistry.setCurveResolver(address(curveResolver));

        _setupOracles(_systemRegistry);

        vm.stopBroadcast();
    }

    function _setupOracles(SystemRegistry systemRegistry) internal {
        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        console.log("Root price Oracle", address(rootPriceOracle));

        CurveV1StableEthOracle curveV1Oracle =
            new CurveV1StableEthOracle(systemRegistry, systemRegistry.curveResolver());
        CurveV2CryptoEthOracle curveV2Oracle =
            new CurveV2CryptoEthOracle(systemRegistry, systemRegistry.curveResolver());
        BalancerLPMetaStableEthOracle balancerMetaOracle = new BalancerLPMetaStableEthOracle(
            systemRegistry, IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8)
        );

        _registerBaseTokens(rootPriceOracle);
        _registerIncentiveTokens(rootPriceOracle);
        _registerBalancerMeta(rootPriceOracle, balancerMetaOracle);
        _registerCurveSet2(rootPriceOracle, curveV2Oracle);
        _registerCurveSet1(rootPriceOracle, curveV1Oracle);

        rootPriceOracle.setSafeSpotPriceThreshold(RETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WETH9_ADDRESS, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CURVE_ETH, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CBETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WSTETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(STETH_MAINNET, 200);
    }

    function _registerBaseTokens(RootPriceOracle rootPriceOracle) internal {
        address wstEthOracle = 0xA93F316ef40848AeaFCd23485b6044E7027b5890;
        address ethPegOracle = 0x58374B8fF79f4C40Fb66e7ca8B13A08992125821;
        address chainlinkOracle = 0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72;

        rootPriceOracle.registerMapping(STETH_MAINNET, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(WSTETH_MAINNET, IPriceOracle(wstEthOracle));
        rootPriceOracle.registerMapping(WETH9_ADDRESS, IPriceOracle(ethPegOracle));
        rootPriceOracle.registerMapping(CURVE_ETH, IPriceOracle(ethPegOracle));
    }

    function _registerIncentiveTokens(RootPriceOracle rootPriceOracle) internal {
        address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address ldo = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        address chainlinkOracle = 0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72;

        rootPriceOracle.registerMapping(crv, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(cvx, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(ldo, IPriceOracle(chainlinkOracle));
    }

    function _registerBalancerMeta(
        RootPriceOracle rootPriceOracle,
        BalancerLPMetaStableEthOracle balMetaOracle
    ) internal {
        // wstETH/WETH - Balancer Meta
        address wstEthWethBalMeta = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        // wstETH/cbETH - Balancer Meta
        address wstEthCbEthBal = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        // rEth/WETH - Balancer Meta
        address rEthWethBalMeta = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

        rootPriceOracle.registerPoolMapping(wstEthWethBalMeta, balMetaOracle);
        rootPriceOracle.registerPoolMapping(wstEthCbEthBal, balMetaOracle);
        rootPriceOracle.registerPoolMapping(rEthWethBalMeta, balMetaOracle);
    }

    function _registerCurveSet2(RootPriceOracle rootPriceOracle, CurveV2CryptoEthOracle curveV2Oracle) internal {
        address curveV2RethEthPool = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
        address curveV2RethEthLpToken = 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C;

        curveV2Oracle.registerPool(curveV2RethEthPool, curveV2RethEthLpToken, true);
        rootPriceOracle.registerMapping(curveV2RethEthLpToken, curveV2Oracle);
        rootPriceOracle.registerPoolMapping(curveV2RethEthPool, curveV2Oracle);

        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;

        curveV2Oracle.registerPool(curveV2cbEthEthPool, curveV2cbEthEthLpToken, true);
        rootPriceOracle.registerMapping(curveV2cbEthEthLpToken, curveV2Oracle);
        rootPriceOracle.registerPoolMapping(curveV2cbEthEthPool, curveV2Oracle);
    }

    function _registerCurveSet1(RootPriceOracle rootPriceOracle, CurveV1StableEthOracle curveV1Oracle) internal {
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;

        curveV1Oracle.registerPool(curveStEthOriginalPool, curveStEthOriginalLpToken, true);
        rootPriceOracle.registerMapping(curveStEthOriginalLpToken, curveV1Oracle);
        rootPriceOracle.registerPoolMapping(curveStEthOriginalPool, curveV1Oracle);

        address curveStEthConcentratedPool = 0x828b154032950C8ff7CF8085D841723Db2696056;
        address curveStEthConcentratedLpToken = 0x828b154032950C8ff7CF8085D841723Db2696056;

        curveV1Oracle.registerPool(curveStEthConcentratedPool, curveStEthConcentratedLpToken, false);
        rootPriceOracle.registerMapping(curveStEthConcentratedLpToken, curveV1Oracle);
        rootPriceOracle.registerPoolMapping(curveStEthConcentratedPool, curveV1Oracle);

        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        curveV1Oracle.registerPool(curveStEthNgPool, curveStEthNgLpToken, false);
        rootPriceOracle.registerMapping(curveStEthNgLpToken, curveV1Oracle);
        rootPriceOracle.registerPoolMapping(curveStEthNgPool, curveV1Oracle);

        address curveRethWstethPool = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveRethWstethLpToken = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;

        curveV1Oracle.registerPool(curveRethWstethPool, curveRethWstethLpToken, false);
        rootPriceOracle.registerMapping(curveRethWstethLpToken, curveV1Oracle);
        rootPriceOracle.registerPoolMapping(curveRethWstethPool, curveV1Oracle);
    }
}
