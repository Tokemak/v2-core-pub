// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/// @dev Scripting specific address file.

// TODO: Change placeholders when able; 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE

enum Systems {
    LST_GEN1_GOERLI,
    LST_GEN1_MAINNET
}

library Constants {
    struct Values {
        string privateKeyEnvVar;
        address weth;
        address toke;
        address systemRegistry;
        address curveMetaRegistry;
        address zeroExProxy;
    }

    function get(Systems system) external pure returns (Values memory) {
        if (system == Systems.LST_GEN1_GOERLI) {
            return getLstGen1Goerli();
        } else if (system == Systems.LST_GEN1_MAINNET) {
            return getLstGen1Mainnet();
        } else {
            revert("address not found");
        }
    }

    function getLstGen1Goerli() private pure returns (Values memory) {
        return Values({
            privateKeyEnvVar: "GOERLI_PRIVATE_KEY",
            weth: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
            toke: 0xdcC9439Fe7B2797463507dD8669717786E51a014,
            systemRegistry: 0x849f823FdC00ADF8AAD280DEA89fe2F7a0be48a3,
            curveMetaRegistry: address(0),
            zeroExProxy: 0xF91bB752490473B8342a3E964E855b9f9a2A668e
        });
    }

    function getLstGen1Mainnet() private pure returns (Values memory) {
        return Values({
            privateKeyEnvVar: "MAINNET_PRIVATE_KEY",
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            toke: 0x2e9d63788249371f1DFC918a52f8d799F4a38C94,
            systemRegistry: address(0),
            curveMetaRegistry: 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC,
            zeroExProxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF
        });
    }
}

// Mainnet
address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant TOKE_MAINNET = 0x2e9d63788249371f1DFC918a52f8d799F4a38C94;
address constant SYSTEM_REGISTRY_MAINNET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address constant CURVE_META_REGISTRY_MAINNET = 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC;

// Goerli
address constant WETH_GOERLI = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
address constant TOKE_GOERLI = 0xdcC9439Fe7B2797463507dD8669717786E51a014;
address constant SYSTEM_REGISTRY_GOERLI = 0x849f823FdC00ADF8AAD280DEA89fe2F7a0be48a3;
