// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IAutopoolFactory } from "src/interfaces/vault/IAutopoolFactory.sol";

contract NewPoolAndStrategy is Script {
    bytes32 public autopoolType = keccak256("lst-guarded-weth-v1");

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        IAutopoolFactory autopoolFactory = constants.sys.systemRegistry.getAutopoolFactoryByType(autopoolType);
        AutopoolETH autopoolTemplate = AutopoolETH(autopoolFactory.template());

        uint256 initialDeposit = autopoolTemplate.WETH_INIT_DEPOSIT();
        constants.sys.systemRegistry.weth().deposit{ value: initialDeposit }();
        constants.sys.systemRegistry.weth().approve(address(autopoolTemplate), initialDeposit);
        AutopoolETH autoPool = AutopoolETH(
            autopoolFactory.createVault{ value: initialDeposit }(
                address(0xC3bB6a6830D14DE99B1B7101d5E60179f6e896eD),
                "balETH_guarded",
                "Balancer/Tokemak Guarded balETH",
                keccak256(abi.encodePacked(block.number)),
                ""
            )
        );

        address[] memory destinations = new address[](14);
        destinations[0] = 0x38e73E98d2038FafdC847F13dd9100732383B6F2;
        destinations[1] = 0xfb1f48a461cCC70081226d8353e45CfBd410dD8F;
        destinations[2] = 0x37e565f997c2b16d2542E906672E9c6281e77954;
        destinations[3] = 0x0b08E02644745e26963c95935A1da19d8D927b97;
        destinations[4] = 0xA6B62bFdc664Af24DDdfF335A167b867f1d590aF;
        destinations[5] = 0xF35fbb601e7de870029691f1872D67A8fC866B15;
        destinations[6] = 0xa3956D49106288E5c04E6FBbBad5b68593f0bE3b;
        destinations[7] = 0xE9D758002676EecCfAc6106c1E31fE04e419c01D;
        destinations[8] = 0x0D883F9600857a28CfBccb16b10095EAcF8055af;
        destinations[9] = 0x5817Cc19A51F92a1fc2806C0228b323fa5be72a0;
        destinations[10] = 0x1E02da6E4DFc4875E372104E5e79d54632F52cB3;
        destinations[11] = 0x8A580F95bF9478C9EC9166E70F5bf2d489C15d8f;
        destinations[12] = 0x9CA9B5dB35e5a48f2B147DaBB8e9848475094669;
        destinations[13] = 0x8C598Be7D29ca09d847275356E1184F166B96931;

        autoPool.addDestinations(destinations);

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        console.log("Autopool address: ", address(autoPool));

        vm.stopBroadcast();
    }
}
