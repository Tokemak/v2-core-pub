// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { Systems } from "../utils/Constants.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { BalancerGyroscopeDestinationVault } from "src/vault/BalancerGyroscopeDestinationVault.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { CurveNGConvexDestinationVault } from "src/vault/CurveNGConvexDestinationVault.sol";
import { Destinations } from "script/core/Destinations.sol";

contract DestinationsDeploy is Script, Destinations {
    Constants.Values public constants;
    address public owner;

    bytes32 public balAuraKey = keccak256(abi.encode("bal-aura-v1"));
    bytes32 public balGyroAuraKey = keccak256(abi.encode("bal-gyro-aura-v1"));
    bytes32 public balKey = keccak256(abi.encode("bal-v1"));
    bytes32 public curveKey = keccak256(abi.encode("crv-cvx-v1"));
    bytes32 public curveNGKey = keccak256(abi.encode("crv-ng-cvx-v1"));

    constructor() Destinations(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        _deployTemplates();

        console.log("");

        _deployBalancerAuraCalculators();

        console.log("");

        _deployCurveConvexCalculators();

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();

        console.log("\n\n  **************************************");
        console.log("======================================");
        console.log("Remember to put any libraries that were deployed into the foundry.toml");
        console.log("======================================");
        console.log("**************************************\n\n");
    }

    function _deployTemplates() private {
        BalancerAuraDestinationVault balAuraVault = new BalancerAuraDestinationVault(
            constants.sys.systemRegistry, address(constants.ext.balancerVault), constants.tokens.aura
        );

        BalancerGyroscopeDestinationVault balGyroAuraVault = new BalancerGyroscopeDestinationVault(
            constants.sys.systemRegistry, address(constants.ext.balancerVault), constants.tokens.aura
        );

        BalancerDestinationVault balVault =
            new BalancerDestinationVault(constants.sys.systemRegistry, address(constants.ext.balancerVault));

        CurveConvexDestinationVault curveVault = new CurveConvexDestinationVault(
            constants.sys.systemRegistry, constants.tokens.cvx, constants.ext.convexBooster
        );

        CurveNGConvexDestinationVault curveNGVault = new CurveNGConvexDestinationVault(
            constants.sys.systemRegistry, constants.tokens.cvx, constants.ext.convexBooster
        );

        console.log("Bal Aura Vault Template - bal-aura-v1: ", address(balAuraVault));
        console.log("Bal Gyro Aura Vault Template - bal-gyro-aura-v1: ", address(balGyroAuraVault));
        console.log("Bal Vault Template - bal-v1: ", address(balVault));
        console.log("Curve Convex Vault Template - crv-cvx-v1: ", address(curveVault));
        console.log("CurveNG Convex Vault Template - crv-ng-cvx-v1: ", address(curveNGVault));

        bytes32[] memory keys = new bytes32[](5);
        keys[0] = balAuraKey;
        keys[1] = curveKey;
        keys[2] = curveNGKey;
        keys[3] = balKey;
        keys[4] = balGyroAuraKey;

        address[] memory addresses = new address[](5);
        addresses[0] = address(balAuraVault);
        addresses[1] = address(curveVault);
        addresses[2] = address(curveNGVault);
        addresses[3] = address(balVault);
        addresses[4] = address(balGyroAuraVault);

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        DestinationRegistry destRegistry = DestinationRegistry(constants.sys.destinationTemplateRegistry);
        destRegistry.addToWhitelist(keys);
        destRegistry.register(keys, addresses);

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);
    }

    function _deployBalancerAuraCalculators() private {
        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "rETH/WETH",
                balancerPool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
                auraStaking: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
                auraPoolId: 109
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "WETH/osETH",
                balancerPool: 0xDACf5Fa19b1f720111609043ac67A9818262850c,
                auraStaking: 0x5F032f15B4e910252EDaDdB899f7201E89C8cD6b,
                auraPoolId: 179
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "wstETH/WETH",
                balancerPool: 0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD,
                auraStaking: 0x2a14dB8D09dB0542f6A371c0cB308A768227D67D,
                auraPoolId: 153
            })
        );

        setupBalancerGyroAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "wstETH/WETH (Gyro)",
                balancerPool: 0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1,
                auraStaking: 0x35113146E7f2dF77Fb40606774e0a3F402035Ffb,
                auraPoolId: 162
            })
        );

        setupBalancerGyroAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "wstETH/cbETH (Gyro)",
                balancerPool: 0xF7A826D47c8E02835D94fb0Aa40F0cC9505cb134,
                auraStaking: 0xC2E2D76a5e02eA65Ecd3be6c9cd3Fa29022f4548,
                auraPoolId: 161
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "wstETH/ETHx",
                balancerPool: 0xB91159aa527D4769CB9FAf3e4ADB760c7E8C8Ea7,
                auraStaking: 0x571a20C14a7c3Ac6d30Ee7D1925940bb0C027696,
                auraPoolId: 207
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "pxETH/WETH",
                balancerPool: 0x88794C65550DeB6b4087B7552eCf295113794410,
                auraStaking: 0x570eA5C8A528E3495EE9883910012BeD598E8814,
                auraPoolId: 185
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "ezETH/WETH",
                balancerPool: 0x596192bB6e41802428Ac943D2f1476C1Af25CC0E,
                auraStaking: 0x95eC73Baa0eCF8159b4EE897D973E41f51978E50,
                auraPoolId: 189
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "rETH/weETH",
                balancerPool: 0x05ff47AFADa98a98982113758878F9A8B9FddA0a,
                auraStaking: 0x07A319A023859BbD49CC9C38ee891c3EA9283Cc5,
                auraPoolId: 182
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "ezETH/weETH/rswETH",
                balancerPool: 0x848a5564158d84b8A8fb68ab5D004Fae11619A54,
                auraStaking: 0xce98eb8b2Fb98049b3F2dB0A212Ba7ca3Efd63b0,
                auraPoolId: 198
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "rsETH/WETH",
                balancerPool: 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D,
                auraStaking: 0xB5FdB4f75C26798A62302ee4959E4281667557E0,
                auraPoolId: 221
            })
        );

        setupBalancerAuraDestinationVault(
            constants,
            BalancerAuraSetup({
                name: "rsETH/ETHx",
                balancerPool: 0x7761b6E0Daa04E70637D81f1Da7d186C205C2aDE,
                auraStaking: 0xf618102462Ff3cf7edbA4c067316F1C3AbdbA193,
                auraPoolId: 191
            })
        );
    }

    function _deployCurveConvexCalculators() private {
        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "osETH/rETH",
                curvePool: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                curveLpToken: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                convexStaking: 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e,
                convexPoolId: 268
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "ETH/OETH",
                curvePool: 0x94B17476A93b3262d87B9a326965D1E91f9c13E7,
                curveLpToken: 0x94B17476A93b3262d87B9a326965D1E91f9c13E7,
                convexStaking: 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A,
                convexPoolId: 174
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "ETH/ETHx",
                curvePool: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                curveLpToken: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                convexStaking: 0x399e111c7209a741B06F8F86Ef0Fdd88fC198D20,
                convexPoolId: 232
            })
        );

        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "WETH/rETH",
                curvePool: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                curveLpToken: 0x9EfE1A1Cbd6Ca51Ee8319AFc4573d253C3B732af,
                convexStaking: 0x2686e9E88AAc7a3B3007CAD5b7a2253438cac6D4,
                convexPoolId: 287
            })
        );

        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "pxETH/stETH",
                curvePool: 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6,
                curveLpToken: 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6,
                convexStaking: 0x633556C8413FCFd45D83656290fF8d64EE41A7c1,
                convexPoolId: 273
            })
        );

        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "WETH/pxETH",
                curvePool: 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
                curveLpToken: 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
                convexStaking: 0x3B793E505A3C7dbCb718Fe871De8eBEf7854e74b,
                convexPoolId: 271
            })
        );

        setupCurveConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "WETH/frxETH",
                curvePool: 0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc,
                curveLpToken: 0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc,
                convexStaking: 0xFafDE12dC476C4913e29F47B4747860C148c5E4f,
                convexPoolId: 219
            })
        );

        setupCurveNGConvexDestinationVault(
            constants,
            CurveConvexSetup({
                name: "WETH/weETH-ng",
                curvePool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                curveLpToken: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                convexStaking: 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58,
                convexPoolId: 355
            })
        );
    }
}
