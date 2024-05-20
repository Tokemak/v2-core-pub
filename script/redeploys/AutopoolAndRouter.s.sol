// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";

contract Liquidator is Script {
    bytes32 public autopoolType = keccak256("lst-guarded-weth-v1");

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        AutopoolETH autoPoolTemplate =
            new AutopoolETH(constants.sys.systemRegistry, address(constants.sys.systemRegistry.weth()), true);
        console.log("Autopool Template: ", address(autoPoolTemplate));

        AutopoolFactory autoPoolFactory =
            new AutopoolFactory(constants.sys.systemRegistry, address(autoPoolTemplate), 800, 100);
        constants.sys.systemRegistry.setAutopoolFactory(autopoolType, address(autoPoolFactory));
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        console.log("AutopoolETH Factory: ", address(autoPoolFactory));

        autoPoolFactory.addStrategyTemplate(0xDD443378E241Eb35Dcf222D2d47763c277157600);

        uint256 initialDeposit = autoPoolTemplate.WETH_INIT_DEPOSIT();
        constants.sys.systemRegistry.weth().deposit{ value: initialDeposit }();
        constants.sys.systemRegistry.weth().approve(address(autoPoolFactory), initialDeposit);
        address autoPool = autoPoolFactory.createVault{ value: initialDeposit }(
            0xDD443378E241Eb35Dcf222D2d47763c277157600,
            "autoETH_guarded_gen2",
            "Tokemak Guarded autoETH Gen2",
            keccak256(abi.encodePacked(block.number)),
            ""
        );

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, owner);

        console.log("Autopool address: ", autoPool);

        AutopilotRouter router = new AutopilotRouter(constants.sys.systemRegistry);
        console.log("AutopoolRouter: ", address(router));

        vm.stopBroadcast();
    }
}
