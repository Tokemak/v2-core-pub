// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";

import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { IDestinationVaultFactory } from "src/interfaces/vault/IDestinationVaultFactory.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { AccessController } from "src/security/AccessController.sol";

import { Roles } from "src/libs/Roles.sol";

contract SetupDestinationVaults is BaseScript {
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        console.log("Owner: ", owner);

        address incentiveCalculator = vm.envAddress("incentive_calculator");

        IDestinationVaultFactory factory = IDestinationVaultFactory(constants.sys.destinationVaultFactory);

        AccessController access = AccessController(constants.sys.accessController);
        access.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, owner);

        systemRegistry.addRewardToken(constants.tokens.weth);
        //systemRegistry.addRewardToken(constants.tokens.toke);

        // Composable
        address poolAddress = constants.pools.balCompSfrxethWstethRethV1;
        address[] memory additionalTrackTokens = new address[](0);
        bytes32 salt = keccak256("gp1");
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: poolAddress,
            auraStaking: address(1),
            auraBooster: address(1),
            auraPoolId: 1
        });

        bytes memory encodedParams = abi.encode(initParams);
        address newVault = factory.create(
            "bal-v1-no-aura",
            constants.tokens.weth,
            poolAddress,
            incentiveCalculator,
            additionalTrackTokens,
            salt,
            encodedParams
        );
        console.log("Composable Destination Vault: ", newVault);

        // Meta
        poolAddress = constants.pools.balMetaWethWsteth;
        salt = keccak256("gp2");
        initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: poolAddress,
            auraStaking: address(1),
            auraBooster: address(1),
            auraPoolId: 1
        });
        encodedParams = abi.encode(initParams);
        newVault = factory.create(
            "bal-v1-no-aura",
            constants.tokens.weth,
            poolAddress,
            incentiveCalculator,
            additionalTrackTokens,
            salt,
            encodedParams
        );
        console.log("Meta Destination Vault: ", newVault);

        vm.stopBroadcast();
    }
}
