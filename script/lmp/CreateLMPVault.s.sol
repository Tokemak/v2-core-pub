// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,gas-custom-errors

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";

/**
 * @dev This contract:
 *      1. Creates a new LMP Vault using the `lst-guarded-r1` LMP Vault Factory and the specified strategy template.
 */
contract CreateLMPVault is BaseScript {
    // 🚨 Manually set variables below. 🚨
    string public lmp1SymbolSuffix = "autoETH_guarded";
    string public lmp1DescPrefix = "Tokemak Guarded autoETH ";
    address public strategyTemplateAddress = 0x86Bd762B375f5B17e6e3a964B01980a53536E3b2;

    bytes32 public lmpVaultType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        LMPVaultFactory lmpFactory = LMPVaultFactory(address(systemRegistry.getLMPVaultFactoryByType(lmpVaultType)));

        accessController.setupRole(Roles.REGISTRY_UPDATER, address(lmpFactory));

        bool isTemplate = lmpFactory.isStrategyTemplate(strategyTemplateAddress);

        if (!isTemplate) {
            revert("Strategy template not found");
        }

        // Initial LMP Vault creation.
        address lmpVault = lmpFactory.createVault(
            strategyTemplateAddress, lmp1SymbolSuffix, lmp1DescPrefix, keccak256(abi.encodePacked(block.number)), ""
        );
        console.log("LMP Vault address: ", lmpVault);

        vm.stopBroadcast();
    }
}
