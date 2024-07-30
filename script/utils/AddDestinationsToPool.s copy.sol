// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { Roles } from "src/libs/Roles.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { console } from "forge-std/console.sol";

contract AddDestinationsToPool is Script {
    address public autoPool = 0x49C4719EaCc746b87703F964F09C22751F397BA0;

    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        (, address owner,) = vm.readCallers();

        AutopoolETH autopool = AutopoolETH(autoPool);

        address[] memory allDestinations = constants.sys.systemRegistry.destinationVaultRegistry().listVaults();
        address[] memory validDestinations = new address[](allDestinations.length);
        uint256 v = 0;
        for (uint256 i = 0; i < allDestinations.length; i++) {
            IDestinationVault destVault = IDestinationVault(allDestinations[i]);
            if (destVault.isShutdown()) {
                console.log("Skipped - shutdown:", address(destVault));
                continue;
            }
            IDexLSTStats calculator = destVault.getStats();
            IDexLSTStats.DexLSTStatsData memory stats = calculator.current();
            if (stats.lastSnapshotTimestamp < (block.timestamp - 2 days)) {
                console.log("Skipped - not warm or stale:", address(destVault));
                continue;
            }
            if (autopool.isDestinationRegistered(address(destVault))) {
                console.log("Skipped - already registered:", address(destVault));
                continue;
            }

            bool brk = false;
            for (uint256 lst = 0; lst < stats.lstStatsData.length; lst++) {
                if (!(stats.lstStatsData[lst].baseApr == 0 && stats.lstStatsData[lst].lastSnapshotTimestamp == 0)) {
                    if (stats.lstStatsData[lst].lastSnapshotTimestamp < (block.timestamp - 3 days)) {
                        console.log("Skipped - not warm or stale lst:", address(destVault));
                        brk = true;
                        break;
                    }
                }
            }
            if (brk) {
                continue;
            }

            validDestinations[v] = allDestinations[i];
            console.log("Added: ", address(destVault));
            ++v;
        }
        address[] memory toAdd = new address[](v);
        for (uint256 i = 0; i < v; i++) {
            toAdd[i] = validDestinations[i];
        }

        vm.startBroadcast();

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);
        autopool.addDestinations(toAdd);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        vm.stopBroadcast();
    }
}
