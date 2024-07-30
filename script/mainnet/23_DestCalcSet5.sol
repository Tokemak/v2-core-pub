// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Script } from "forge-std/Script.sol";
import { Destinations } from "script/core/Destinations.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { BalancerGyroPoolCalculator } from "src/stats/calculators/BalancerGyroPoolCalculator.sol";
import { console } from "forge-std/console.sol";
import { BalancerGyroscopeDestinationVault } from "src/vault/BalancerGyroscopeDestinationVault.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";

contract DestCalcSet5 is Script, Destinations {
    Constants.Values public constants;

    // LST Template Ids
    bytes32 public balAuraGyroKey = keccak256(abi.encode("bal-aura-gyro-v1"));
    bytes32 internal balGyroDexTemplateId = keccak256("dex-balGyro");

    constructor() Destinations(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        // Deploy Balancer Gyro Destination Vault Template
        BalancerGyroscopeDestinationVault balGyroAuraVault = new BalancerGyroscopeDestinationVault(
            constants.sys.systemRegistry, address(constants.ext.balancerVault), constants.tokens.aura
        );
        console.log("Bal Gyro Aura Template: bal-aura-gyro-v1", address(balGyroAuraVault));
        console.log("\nbal-aura-gyro-v1: ");
        console.logBytes32(balAuraGyroKey);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = balAuraGyroKey;

        address[] memory addresses = new address[](1);
        addresses[0] = address(balGyroAuraVault);

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        DestinationRegistry destRegistry = DestinationRegistry(constants.sys.destinationTemplateRegistry);
        destRegistry.addToWhitelist(keys);
        destRegistry.register(keys, addresses);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, owner);

        // Deploy Balancer Gyro DEX Calculator Template
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        BalancerGyroPoolCalculator gyroDexCalcTemplate =
            new BalancerGyroPoolCalculator(constants.sys.systemRegistry, address(constants.ext.balancerVault));
        constants.sys.statsCalcFactory.registerTemplate(balGyroDexTemplateId, address(gyroDexCalcTemplate));
        console.log("-------------------------");
        console.log("Balancer Gyro Aura Dest Vault Template:", address(gyroDexCalcTemplate));
        console.logBytes32(balGyroDexTemplateId);
        console.log("-------------------------");

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        bytes32[] memory depLstsCalcs = new bytes32[](2);
        depLstsCalcs[0] = keccak256(abi.encode("lst", constants.tokens.wstEth));
        depLstsCalcs[1] = Stats.NOOP_APR_ID;

        deployBalancerGyroAura(
            constants,
            BalancerAuraDestCalcSetup({
                name: "wstETH/WETH",
                poolAddress: 0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0x35113146E7f2dF77Fb40606774e0a3F402035Ffb,
                poolId: 162
            })
        );

        depLstsCalcs[0] = keccak256(abi.encode("lst", constants.tokens.wstEth));
        depLstsCalcs[1] = Stats.generateRawTokenIdentifier(constants.tokens.cbEth);

        deployBalancerGyroAura(
            constants,
            BalancerAuraDestCalcSetup({
                name: "wstETH/cbETH",
                poolAddress: 0xF7A826D47c8E02835D94fb0Aa40F0cC9505cb134,
                dependentPoolCalculators: depLstsCalcs,
                rewarderAddress: 0xC2E2D76a5e02eA65Ecd3be6c9cd3Fa29022f4548,
                poolId: 161
            })
        );

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        vm.stopBroadcast();
    }
}
