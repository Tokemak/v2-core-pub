// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,gas-custom-errors

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";

/**
 * @dev This contract:
 *      1. Creates a new Autopool Vault using the `lst-guarded-r1` Autopool Vault Factory and the specified strategy
 * template.
 */
contract CreateAutopoolETH is BaseScript {
    // 🚨 Manually set variables below. 🚨
    string public autoPool1SymbolSuffix = "autoETH_guarded";
    string public autoPool1DescPrefix = "Tokemak Guarded autoETH ";
    address public strategyTemplateAddress = 0x86Bd762B375f5B17e6e3a964B01980a53536E3b2;

    bytes32 public autoPoolType = keccak256("lst-guarded-r1");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        AutopoolFactory autoPoolFactory =
            AutopoolFactory(address(systemRegistry.getAutopoolFactoryByType(autoPoolType)));

        accessController.setupRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));

        bool isTemplate = autoPoolFactory.isStrategyTemplate(strategyTemplateAddress);

        if (!isTemplate) {
            revert("Strategy template not found");
        }

        // Initial Autopool Vault creation.
        address autoPool = autoPoolFactory.createVault(
            strategyTemplateAddress,
            autoPool1SymbolSuffix,
            autoPool1DescPrefix,
            keccak256(abi.encodePacked(block.number)),
            ""
        );
        console.log("Autopool Vault address: ", autoPool);

        vm.stopBroadcast();
    }
}
