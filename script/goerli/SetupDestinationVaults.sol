// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { ERC20Mock } from "script/mocks/ERC20Mock.sol";
import { MockRateProvider, IRateProvider } from "script/mocks/MockRateProvider.sol";
import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { IDestinationVaultFactory } from "src/interfaces/vault/IDestinationVaultFactory.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
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

        IDestinationVaultFactory factory = IDestinationVaultFactory(constants.sys.destinationVaultFactory);

        AccessController access = AccessController(constants.sys.accessController);
        access.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, owner);

        systemRegistry.addRewardToken(constants.tokens.weth);
        //systemRegistry.addRewardToken(constants.tokens.toke);

        // Composable
        address poolAddress = 0x9d6d991f9dd88a93F31C1a61BccdbbC9abCF5657;
        address[] memory addtlTrackTokens = new address[](0);
        bytes32 salt = keccak256("gp1");
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: poolAddress,
            auraStaking: address(1),
            auraBooster: address(1),
            auraPoolId: 1
        });
        bytes memory encodedParams = abi.encode(initParams);
        address newVault =
            factory.create("bal-v1-no-aura", constants.tokens.weth, poolAddress, addtlTrackTokens, salt, encodedParams);
        console.log("Composable Destination Vault: ", newVault);

        // Meta
        poolAddress = 0x26B8Cf12405861e68230154674cE49253C3ee19b;
        salt = keccak256("gp2");
        initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: poolAddress,
            auraStaking: address(1),
            auraBooster: address(1),
            auraPoolId: 1
        });
        encodedParams = abi.encode(initParams);
        newVault =
            factory.create("bal-v1-no-aura", constants.tokens.weth, poolAddress, addtlTrackTokens, salt, encodedParams);
        console.log("Meta Destination Vault: ", newVault);

        vm.stopBroadcast();
    }
}
