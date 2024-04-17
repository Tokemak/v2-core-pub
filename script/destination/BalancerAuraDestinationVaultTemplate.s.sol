// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string,state-visibility,const-name-snakecase,gas-custom-errors

import { Systems } from "script/utils/Constants.sol";
import { BaseScript, console } from "script/BaseScript.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";

contract BalancerAuraDestinationVaultTemplate is BaseScript {
    bytes32 constant dvType = keccak256(abi.encode("balancer-aura"));

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        if (address(destinationTemplateRegistry) == address(0)) {
            revert("Destination Template Registry not set");
        }

        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        if (!destinationTemplateRegistry.isWhitelistedDestination(dvType)) {
            destinationTemplateRegistry.addToWhitelist(dvTypes);
        }

        BalancerAuraDestinationVault dv =
            new BalancerAuraDestinationVault(systemRegistry, constants.ext.balancerVault, constants.tokens.aura);

        console.log("Balancer Aura Destination Vault Template:", address(dv));

        address[] memory dvs = new address[](1);
        dvs[0] = address(0xE1E5EAe3A9fF680347D8Fb7a622017bdb424DBED);

        destinationTemplateRegistry.register(dvTypes, dvs);

        vm.stopBroadcast();
    }
}
