// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SystemRegistry } from "src/SystemRegistry.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";

import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";

/* solhint-disable gas-custom-errors */

// TODO: Change placeholders when able; 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE

enum Systems {
    NEW_MAINNET,
    NEW_BASE,
    NEW_SEPOLIA,
    LST_GEN1_MAINNET,
    LST_GEN2_MAINNET,
    LST_GEN1_BASE,
    LST_GEN1_SEPOLIA
}

library Constants {
    struct Tokens {
        address toke;
        address weth;
        address bal;
        address crv;
        address cvx;
        address ldo;
        address rpl;
        address swise;
        address wstEth;
        address curveEth;
        address swEth;
        address stEth;
        address cbEth;
        address rEth;
        address sfrxEth;
        address aura;
        address osEth;
        address aero;
        address ezEth;
    }

    struct System {
        SystemRegistry systemRegistry;
        AccessController accessController;
        address destinationTemplateRegistry;
        DestinationVaultFactory destinationVaultFactory;
        address swapRouter;
        address lens;
        address systemSecurity;
        StatsCalculatorRegistry statsCalcRegistry;
        StatsCalculatorFactory statsCalcFactory;
        ICurveResolver curveResolver;
        RootPriceOracle rootPriceOracle;
        SystemOracles subOracles;
        IncentivePricingStats incentivePricing;
        AsyncSwappers asyncSwappers;
    }

    struct SystemOracles {
        ChainlinkOracle chainlink;
        EthPeggedOracle ethPegged;
        CurveV1StableEthOracle curveV1;
        CurveV2CryptoEthOracle curveV2;
        BalancerLPMetaStableEthOracle balancerMeta;
        address balancerComp;
        WstETHEthOracle wstEth;
        RedstoneOracle redStone;
        CustomSetOracle customSet;
    }

    struct AsyncSwappers {
        address zeroEx;
        address propellerHead;
        address liFi;
    }

    struct External {
        address curveMetaRegistry;
        address convexBooster;
        address auraBooster;
        address zeroExProxy;
        IBalancerVault balancerVault;
        address mavRouter;
        address mavPoolFactory;
        address mavBoostedPositionFactory;
    }

    struct Values {
        Tokens tokens;
        System sys;
        External ext;
    }

    function get(Systems system) internal view returns (Values memory) {
        if (system == Systems.LST_GEN1_MAINNET) {
            return getLstGen1Mainnet();
        } else if (system == Systems.LST_GEN2_MAINNET) {
            return getLstGen2Mainnet();
        } else if (system == Systems.NEW_MAINNET) {
            return getEmptyMainnet();
        } else if (system == Systems.NEW_BASE) {
            return getEmptyBase();
        } else if (system == Systems.LST_GEN1_BASE) {
            return getLstGen1Base();
        } else if (system == Systems.NEW_SEPOLIA) {
            return getEmptySepolia();
        } else if (system == Systems.LST_GEN1_SEPOLIA) {
            return getLstGen1Sepolia();
        } else {
            revert("address not found");
        }
    }

    function getEmptySepolia() private pure returns (Values memory) {
        return Values({ tokens: getSepoliaTokens(), sys: getEmptySystem(), ext: getSepoliaExternal() });
    }

    function getEmptyMainnet() private pure returns (Values memory) {
        return Values({ tokens: getMainnetTokens(), sys: getEmptySystem(), ext: getMainnetExternal() });
    }

    function getEmptyBase() private pure returns (Values memory) {
        return Values({ tokens: getBaseTokens(), sys: getEmptySystem(), ext: getBaseExternal() });
    }

    function getLstGen1Base() private view returns (Values memory) {
        System memory sys =
            getQueryableSystem(0xBa69A35D353Af239B12db3c5C90b1EB09F52e3dd, 0x1523738df2c6Cc303B6A919de69a976056848C80);

        return Values({ tokens: getBaseTokens(), sys: sys, ext: getBaseExternal() });
    }

    function getLstGen1Sepolia() private view returns (Values memory) {
        System memory sys =
            getQueryableSystem(0x25F603C1a0Ce130c7F25321A7116379d3c270c23, 0xAfB384E53F891BA020524E13a7c4DE4E0898Dcf8);

        sys.asyncSwappers = AsyncSwappers({
            zeroEx: 0x266882e796dA0aFD36392036F9eC11Fa32e36a62,
            propellerHead: address(0),
            liFi: address(0)
        });

        return Values({ tokens: getSepoliaTokens(), sys: sys, ext: getSepoliaExternal() });
    }

    function getLstGen2Mainnet() private view returns (Values memory) {
        System memory sys =
            getQueryableSystem(0xB20193f43C9a7184F3cbeD9bAD59154da01488b4, 0xFCC0F0D25E4c7c0DFB5D5a50869183C44429CF9D);

        sys.subOracles = SystemOracles({
            chainlink: ChainlinkOracle(0x20fb0284c2748136aD5212223bD66a9180469cA7),
            ethPegged: EthPeggedOracle(0xEAb103E352e7A66a8d0Bad1F4088a423E92d0D97),
            curveV1: CurveV1StableEthOracle(0x9F4ccD800848ee15CAb538E636d3de9C9f340A53),
            curveV2: CurveV2CryptoEthOracle(0x401070e4394219Fac55473d786579b2C88f6b3c2),
            balancerMeta: BalancerLPMetaStableEthOracle(0xC60535Ce2dF8c4ff203f9729e0aF196F8231EACA),
            balancerComp: address(0),
            wstEth: WstETHEthOracle(0xe383DBF350f6A8d0cE4b4654Acaa60E04FfA6c67),
            redStone: RedstoneOracle(0x23a7d7707f80a26495ac73B15Db6F4FA541164F7),
            customSet: CustomSetOracle(0x107a0ffA06595A5A2491C974CB2C8541Fc7FBccA)
        });

        sys.asyncSwappers = AsyncSwappers({
            zeroEx: 0xCAA2aaf87598701dbBb6240C9A19109ACD936e13,
            propellerHead: 0xaA58f93e1Fb86199DdF12a61aB9429d85B6C8341,
            liFi: 0x369E19c3Aa355196340F4b8Cc97E39c1858380c1
        });

        return Values({ tokens: getMainnetTokens(), sys: sys, ext: getMainnetExternal() });
    }

    function getLstGen1Mainnet() private pure returns (Values memory) {
        return Values({
            tokens: getMainnetTokens(),
            sys: System({
                systemRegistry: SystemRegistry(0x0406d2D96871f798fcf54d5969F69F55F803eEA4),
                accessController: AccessController(0x7f3B9EEaF70bD5186E7e226b7f683b67eb3eD5Fd),
                destinationTemplateRegistry: 0x44e02280bbc2A1a1214C4959747F2EC2D9cFf237,
                destinationVaultFactory: DestinationVaultFactory(0xbefd2500435bC49107aE54Ac8ea0716b989313a1),
                swapRouter: address(0),
                lens: address(0),
                systemSecurity: 0x5e72DE713a4782563E4E6bA39D28699F0E053d66,
                statsCalcRegistry: StatsCalculatorRegistry(0x257b2A2179Cf0586da51d9856463fe5dF9E6e5F9),
                statsCalcFactory: StatsCalculatorFactory(0x6AF0984Ca9E707a4dc3F22266eCF37515E47ec3c),
                curveResolver: ICurveResolver(0x118871DA329cFC4b45219BE37dFc2a5C27e469DF),
                rootPriceOracle: RootPriceOracle(0x3b3188c10cb9E2d3A331a4EfAD05B70bdEA1b08e),
                incentivePricing: IncentivePricingStats(0xD2F09D4e3110F397c2a536081f13Fe08D9868c82),
                subOracles: SystemOracles({
                    chainlink: ChainlinkOracle(0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72),
                    ethPegged: EthPeggedOracle(0x58374B8fF79f4C40Fb66e7ca8B13A08992125821),
                    curveV1: CurveV1StableEthOracle(0xc3fD8f8C544adc02aFF22C31a9aBAd0c3f79a672),
                    curveV2: CurveV2CryptoEthOracle(0x075c80cd9E8455F94b7Ea6EDB91485F2D974FB9B),
                    balancerMeta: BalancerLPMetaStableEthOracle(0xeaD83A1A04f730b428055151710ba38e886b644e),
                    balancerComp: 0x2BB64D96B0DCfaB7826D11707AAE3F55409d8E19,
                    wstEth: WstETHEthOracle(0xA93F316ef40848AeaFCd23485b6044E7027b5890),
                    redStone: RedstoneOracle(0x9E16879c6F4415Ce5EBE21816C51F476AEEc49bE),
                    customSet: CustomSetOracle(0x58e161B002034f1F94858613Da0967EB985EB3D0)
                }),
                asyncSwappers: AsyncSwappers({ zeroEx: address(0), propellerHead: address(0), liFi: address(0) })
            }),
            ext: getMainnetExternal()
        });
    }

    function getEmptySystem() private pure returns (System memory) { }

    function getQueryableSystem(address systemRegistryAddress, address lens) private view returns (System memory sys) {
        SystemRegistry systemRegistry = SystemRegistry(systemRegistryAddress);

        sys.systemRegistry = systemRegistry;
        sys.accessController = AccessController(address(systemRegistry.accessController()));
        sys.destinationTemplateRegistry = address(systemRegistry.destinationTemplateRegistry());
        sys.destinationVaultFactory =
            DestinationVaultFactory(address(systemRegistry.destinationVaultRegistry().factory()));
        sys.swapRouter = address(systemRegistry.swapRouter());
        sys.lens = lens;
        sys.systemSecurity = address(systemRegistry.systemSecurity());
        sys.statsCalcRegistry = StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry()));
        sys.statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );
        sys.curveResolver = systemRegistry.curveResolver();
        sys.rootPriceOracle = RootPriceOracle(address(systemRegistry.rootPriceOracle()));
        sys.incentivePricing = IncentivePricingStats(address(systemRegistry.incentivePricing()));
    }

    function getMainnetExternal() private pure returns (External memory) {
        return External({
            convexBooster: 0xF403C135812408BFbE8713b5A23a04b3D48AAE31,
            auraBooster: 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234,
            curveMetaRegistry: 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC,
            zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
            balancerVault: IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8),
            mavRouter: 0xbBF1EE38152E9D8e3470Dc47947eAa65DcA94913,
            mavPoolFactory: 0xEb6625D65a0553c9dBc64449e56abFe519bd9c9B,
            mavBoostedPositionFactory: 0x4F24D73773fCcE560f4fD641125c23A2B93Fcb05
        });
    }

    function getMainnetTokens() private pure returns (Tokens memory) {
        return Tokens({
            toke: 0x2e9d63788249371f1DFC918a52f8d799F4a38C94,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            bal: 0xba100000625a3754423978a60c9317c58a424e3D,
            cvx: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            ldo: 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32,
            rpl: 0xD33526068D116cE69F19A9ee46F0bd304F21A51f,
            swise: 0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2,
            wstEth: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            curveEth: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            swEth: 0xf951E335afb289353dc249e82926178EaC7DEd78,
            stEth: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            cbEth: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704,
            rEth: 0xae78736Cd615f374D3085123A210448E74Fc6393,
            sfrxEth: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            aura: 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF,
            osEth: 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38,
            aero: address(0),
            ezEth: 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110
        });
    }

    function getBaseTokens() private pure returns (Tokens memory) {
        return Tokens({
            toke: 0x000000000000000000000000000000000000F043,
            weth: 0x4200000000000000000000000000000000000006,
            bal: 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1,
            cvx: address(0),
            crv: address(0),
            ldo: address(0),
            rpl: address(0),
            swise: address(0),
            wstEth: 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452,
            curveEth: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            swEth: address(0),
            stEth: address(0),
            cbEth: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
            rEth: 0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c,
            sfrxEth: address(0),
            aura: 0x1509706a6c66CA549ff0cB464de88231DDBe213B,
            osEth: address(0),
            aero: 0x940181a94A35A4569E4529A3CDfB74e38FD98631,
            ezEth: 0x2416092f143378750bb29b79eD961ab195CcEea5
        });
    }

    function getBaseExternal() private pure returns (External memory) {
        return External({
            convexBooster: address(0),
            auraBooster: 0x98Ef32edd24e2c92525E59afc4475C1242a30184,
            curveMetaRegistry: address(0),
            zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
            balancerVault: IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8),
            mavRouter: address(0),
            mavPoolFactory: 0xB2855783a346735e4AAe0c1eb894DEf861Fa9b45,
            mavBoostedPositionFactory: address(0)
        });
    }

    function getSepoliaExternal() private pure returns (External memory) {
        return External({
            convexBooster: address(0),
            auraBooster: address(0),
            curveMetaRegistry: address(0),
            zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
            balancerVault: IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8),
            mavRouter: address(0),
            mavPoolFactory: address(0),
            mavBoostedPositionFactory: address(0)
        });
    }

    function getSepoliaTokens() private pure returns (Tokens memory) {
        return Tokens({
            toke: 0xEec5970a763C0ae3Eb2a612721bD675DdE2561C2,
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            bal: address(0),
            cvx: address(0),
            crv: address(0),
            ldo: address(0),
            rpl: address(0),
            swise: address(0),
            wstEth: address(0),
            curveEth: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            swEth: address(0),
            stEth: address(0),
            cbEth: address(0),
            rEth: address(0),
            sfrxEth: address(0),
            aura: address(0),
            osEth: address(0),
            aero: address(0),
            ezEth: address(0)
        });
    }
}
