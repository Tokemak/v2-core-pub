// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";

contract Destinations is Script {
    uint256 public saltIx;
    Constants.Values public constants;

    struct CurveConvexSetup {
        string name;
        address curvePool;
        address curveLpToken;
        address convexStaking;
        uint256 convexPoolId;
    }

    struct BalancerAuraSetup {
        string name;
        address balancerPool;
        address auraStaking;
        uint256 auraPoolId;
    }

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        setupDestinations();

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function setupDestinations() internal {
        setupBalancerDestinations();
    }

    function setupBalancerDestinations() internal {
        setupBalancerAuraDestinationVault(
            BalancerAuraSetup({
                name: "rETH/WETH",
                balancerPool: 0xC771c1a5905420DAEc317b154EB13e4198BA97D0,
                auraStaking: 0xcCAC11368BDD522fc4DD23F98897712391ab1E00,
                auraPoolId: 7
            })
        );

        setupBalancerAuraDestinationVault(
            BalancerAuraSetup({
                name: "cbETH/WETH",
                balancerPool: 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6,
                auraStaking: 0x8dB6A97AeEa09F37b45C9703c3542087151aAdD5,
                auraPoolId: 3
            })
        );
    }

    function setupBalancerAuraDestinationVault(BalancerAuraSetup memory args) internal {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: args.balancerPool,
            auraStaking: args.auraStaking,
            auraBooster: constants.ext.auraBooster,
            auraPoolId: args.auraPoolId
        });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                "bal-aura-v1",
                constants.tokens.weth,
                initParams.balancerPool,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        keccak256(abi.encode("incentive-v4-", constants.tokens.aura, args.auraStaking))
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Balancer ", args.name, " Dest Vault: "), address(newVault));
    }
}
