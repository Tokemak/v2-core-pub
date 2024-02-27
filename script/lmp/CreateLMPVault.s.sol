// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";

/**
 * @dev This contract:
 *      1. Creates a new LMP Vault using the `weth-vault` LMP Vault Factory and the specified strategy template.
 */
contract CreateLMPVault is BaseScript {
    // 🚨 Manually set variables below. 🚨
    uint256 public lmp1SupplyLimit = type(uint112).max;
    uint256 public lmp1WalletLimit = type(uint112).max;
    string public lmp1SymbolSuffix = "EST";
    string public lmp1DescPrefix = "Established";
    address public strategyTemplateAddress = 0xecE724EB3B0843E21239300479F310251C15851e
    ;

    bytes32 public lmpVaultType = keccak256("weth-vault");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        LMPVaultFactory lmpFactory = LMPVaultFactory(address(systemRegistry.getLMPVaultFactoryByType(lmpVaultType)));

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
