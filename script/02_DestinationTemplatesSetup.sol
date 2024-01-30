// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count
// solhint-disable no-console

import { BaseScript, console } from "./BaseScript.sol";

// Contracts
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { Systems } from "./utils/Constants.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { MaverickDestinationVault } from "src/vault/MaverickDestinationVault.sol";

contract DestinationTemplatesSetupScript is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        vm.startBroadcast(privateKey);

        BalancerAuraDestinationVault balVault =
            new BalancerAuraDestinationVault(systemRegistry, constants.ext.balancerVault, constants.tokens.bal);

        CurveConvexDestinationVault curveVault =
            new CurveConvexDestinationVault(systemRegistry, constants.tokens.cvx, constants.ext.convexBooster);

        MaverickDestinationVault mavVault = new MaverickDestinationVault(systemRegistry);

        console.log("Bal Vault Template - bal-v1-no-aura: ", address(balVault));
        console.log("Curve Vault Template - crv-v1-no-cvx: ", address(curveVault));
        console.log("Mav Vault Template: mav-v1", address(mavVault));

        bytes32 balKey = keccak256(abi.encode("bal-v1-no-aura"));
        bytes32 curveKey = keccak256(abi.encode("crv-v1-no-cvx"));
        bytes32 mavKey = keccak256(abi.encode("mav-v1"));

        bytes32[] memory keys = new bytes32[](3);
        keys[0] = balKey;
        keys[1] = curveKey;
        keys[2] = mavKey;

        address[] memory addresses = new address[](3);
        addresses[0] = address(balVault);
        addresses[1] = address(curveVault);
        addresses[2] = address(mavVault);

        DestinationRegistry destRegistry = DestinationRegistry(constants.sys.destinationTemplateRegistry);
        destRegistry.addToWhitelist(keys);
        destRegistry.register(keys, addresses);

        vm.stopBroadcast();
    }
}
