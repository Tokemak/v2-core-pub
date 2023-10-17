// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

/// @dev Scripting specific address file.

// TODO: Change placeholders when able; 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE

enum Systems {
    LST_GEN1_GOERLI,
    LST_GEN1_MAINNET
}

library Constants {
    struct Tokens {
        address toke;
        address weth;
        address bal;
        address cvx;
        address wstEth;
        address swEth;
        address stEth;
        address cbEth;
        address rEth;
        address sfrxEth;
    }

    struct System {
        address systemRegistry;
        address accessController;
        address destinationTemplateRegistry;
        address destinationVaultFactory;
        address swapRouter;
        address customSetOracle;
        address lens;
    }

    struct External {
        address curveMetaRegistry;
        address convexBooster;
        address zeroExProxy;
        address balancerComposableStableFactory;
        address balancerMetaStableFactor;
        address balancerVault;
        address mavPoolFactory;
        address mavBoostedPositionFactory;
    }

    struct Pools {
        address balCompSfrxethWstethRethV1;
        address balMetaWethWsteth;
    }

    struct Values {
        Tokens tokens;
        System sys;
        External ext;
        Pools pools;
        string privateKeyEnvVar;
    }

    function get(Systems system) external view returns (Values memory) {
        if (system == Systems.LST_GEN1_GOERLI) {
            return getLstGen1Goerli();
        } else if (system == Systems.LST_GEN1_MAINNET) {
            return getLstGen1Mainnet();
        } else {
            revert("address not found");
        }
    }

    function getLstGen1Goerli() private view returns (Values memory) {
        ISystemRegistry registry = ISystemRegistry(0x0FE586aCF3f485BBC99e8CE05af8E2719760Ec7b);

        return Values({
            tokens: Tokens({
                toke: 0xdcC9439Fe7B2797463507dD8669717786E51a014,
                weth: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
                bal: 0xfA8449189744799aD2AcE7e0EBAC8BB7575eff47,
                cvx: address(1),
                wstEth: 0xa0494a297434eBa30e807D983605e8B12259CC21,
                swEth: address(1),
                stEth: address(1),
                cbEth: address(1),
                rEth: 0xf7bb4a608F8DFDc1a31A72bFa089c7f57545CeA9,
                sfrxEth: 0x306C8Ca71f691f7Bb23c14B8fEA13320a35B70A6
            }),
            sys: System({
                systemRegistry: address(registry),
                accessController: address(registry.accessController()),
                destinationTemplateRegistry: address(registry.destinationTemplateRegistry()),
                destinationVaultFactory: address(registry.destinationVaultRegistry().factory()),
                swapRouter: address(registry.swapRouter()),
                customSetOracle: 0x8A1de606ceF7Df46E577e9e1C3c6B45712Ce65d1,
                lens: 0xbE87fb643fF79B427C42baCf5D49DC743Cc8bF3a
            }),
            ext: External({
                curveMetaRegistry: address(0),
                convexBooster: 0xF403C135812408BFbE8713b5A23a04b3D48AAE31,
                zeroExProxy: 0xF91bB752490473B8342a3E964E855b9f9a2A668e,
                balancerComposableStableFactory: 0x4bdCc2fb18AEb9e2d281b0278D946445070EAda7,
                balancerMetaStableFactor: 0xA55F73E2281c60206ba43A3590dB07B8955832Be,
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                mavPoolFactory: 0x6292B737E6640223EB783F1355737315985Ece49,
                mavBoostedPositionFactory: 0x680ca064ACcEbdF5B7B8079924C5D0bb79302285
            }),
            pools: Pools({
                balCompSfrxethWstethRethV1: 0x9d6d991f9dd88a93F31C1a61BccdbbC9abCF5657,
                balMetaWethWsteth: 0x26B8Cf12405861e68230154674cE49253C3ee19b
            }),
            privateKeyEnvVar: "GOERLI_PRIVATE_KEY"
        });
    }

    function getLstGen1Mainnet() private pure returns (Values memory) {
        return Values({
            tokens: Tokens({
                toke: 0x2e9d63788249371f1DFC918a52f8d799F4a38C94,
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                bal: 0xba100000625a3754423978a60c9317c58a424e3D,
                cvx: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
                wstEth: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                swEth: 0xf951E335afb289353dc249e82926178EaC7DEd78,
                stEth: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
                cbEth: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704,
                rEth: 0xae78736Cd615f374D3085123A210448E74Fc6393,
                sfrxEth: 0xac3E018457B222d93114458476f3E3416Abbe38F
            }),
            sys: System({
                systemRegistry: address(0),
                accessController: address(0),
                destinationTemplateRegistry: address(0),
                destinationVaultFactory: address(0),
                swapRouter: address(0),
                customSetOracle: address(0),
                lens: address(0)
            }),
            ext: External({
                convexBooster: 0xF403C135812408BFbE8713b5A23a04b3D48AAE31,
                curveMetaRegistry: 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC,
                zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
                balancerComposableStableFactory: address(0),
                balancerMetaStableFactor: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                mavPoolFactory: 0xEb6625D65a0553c9dBc64449e56abFe519bd9c9B,
                mavBoostedPositionFactory: 0x4F24D73773fCcE560f4fD641125c23A2B93Fcb05
            }),
            pools: Pools({
                balCompSfrxethWstethRethV1: 0x42ED016F826165C2e5976fe5bC3df540C5aD0Af7,
                balMetaWethWsteth: 0x32296969Ef14EB0c6d29669C550D4a0449130230
            }),
            privateKeyEnvVar: "MAINNET_PRIVATE_KEY"
        });
    }
}
