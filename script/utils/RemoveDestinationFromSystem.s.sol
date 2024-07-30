// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";

contract AddDestinationsToPool is Script {
    DestinationVault public toRemove = DestinationVault(0xe3018Ee1e54F2CEb7F363Aa837F905ca509bAB1C);

    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_MANAGER, owner);
        toRemove.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_MANAGER, owner);

        vm.stopBroadcast();
    }
}
