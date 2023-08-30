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
    }

    struct System {
        address systemRegistry;
        address accessController;
        address destinationTemplateRegistry;
        address destinationVaultFactory;
        address lens;
    }

    struct External {
        address curveMetaRegistry;
        address zeroExProxy;
        address balancerComposableStableFactory;
        address balancerMetaStableFactor;
        address balancerVault;
    }

    struct Values {
        Tokens tokens;
        System sys;
        External ext;
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
                cvx: address(1)
            }),
            sys: System({
                systemRegistry: address(registry),
                accessController: address(registry.accessController()),
                destinationTemplateRegistry: address(registry.destinationTemplateRegistry()),
                destinationVaultFactory: address(registry.destinationVaultRegistry().factory()),
                lens: 0xbE87fb643fF79B427C42baCf5D49DC743Cc8bF3a
            }),
            ext: External({
                curveMetaRegistry: address(0),
                zeroExProxy: 0xF91bB752490473B8342a3E964E855b9f9a2A668e,
                balancerComposableStableFactory: 0x4bdCc2fb18AEb9e2d281b0278D946445070EAda7,
                balancerMetaStableFactor: 0xA55F73E2281c60206ba43A3590dB07B8955832Be,
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8
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
                cvx: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B
            }),
            sys: System({
                systemRegistry: address(0),
                accessController: address(0),
                destinationTemplateRegistry: address(0),
                destinationVaultFactory: address(0),
                lens: address(0)
            }),
            ext: External({
                curveMetaRegistry: 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC,
                zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF,
                balancerComposableStableFactory: address(0),
                balancerMetaStableFactor: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8
            }),
            privateKeyEnvVar: "MAINNET_PRIVATE_KEY"
        });
    }
}
