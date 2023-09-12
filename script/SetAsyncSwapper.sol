// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Roles } from "src/libs/Roles.sol";
import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

contract DeployCustomOracle is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("GOERLI_PRIVATE_KEY"));

        AccessController access = AccessController(0xAf647ee0FF2F8696CcaE6414aa42b0299B243231);
        access.grantRole(Roles.REGISTRY_UPDATER, 0xec19A67D0332f3b188740A2ea96F84CA3a17D73a);

        // 0xf91bb752490473b8342a3e964e855b9f9a2a668e - 0x Proxy Goerli
        BaseAsyncSwapper s = new BaseAsyncSwapper(0xF91bB752490473B8342a3E964E855b9f9a2A668e);

        AsyncSwapperRegistry a = AsyncSwapperRegistry(0x88c1A6B8404066048Ef234A2Bb6c034743009206);

        a.register(address(s));

        console.log("Base Async Swapper: %s", address(s));

        vm.stopBroadcast();
    }
}
