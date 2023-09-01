// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";
import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { Lens } from "src/lens/Lens.sol";
import { ILens } from "src/interfaces/lens/ILens.sol";

contract CheckLens is BaseScript {
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        Lens lens = Lens(constants.sys.lens);

        ILens.LMPVault[] memory lmpVaults = lens.getVaults();
        (address[] memory lmpVaultsAddress, ILens.DestinationVault[][] memory destinations) =
            lens.getVaultDestinations();
        (address[] memory dvs, ILens.UnderlyingToken[][] memory tokens) = lens.getVaultDestinationTokens();

        for (uint256 i = 0; i < lmpVaults.length; i++) {
            console.log("----- LMP Vault --------");
            console.log("Address %s", lmpVaults[i].vaultAddress);
            console.log("Name %s", lmpVaults[i].name);
            console.log("Symbol %s", lmpVaults[i].symbol);
            console.log("------------------------");
        }

        for (uint256 i = 0; i < lmpVaultsAddress.length; i++) {
            console.log("----- LMP Vault --------");
            console.log("Address %s", lmpVaultsAddress[i]);
            ILens.DestinationVault[] memory d = destinations[i];
            for (uint256 k = 0; k < d.length; k++) {
                console.log("----- Dest Vault --------");
                console.log("Exchange %s", d[k].exchangeName);
                console.log("Address %s", d[k].vaultAddress);
            }
            console.log("------------------------");
        }

        for (uint256 i = 0; i < dvs.length; i++) {
            console.log("----- Dest Vault --------");
            console.log("Address %s", dvs[i]);
            ILens.UnderlyingToken[] memory d = tokens[i];
            for (uint256 k = 0; k < d.length; k++) {
                console.log("----- Token --------");
                console.log("Symbol %s", d[k].symbol);
                console.log("Address %s", d[k].tokenAddress);
            }
            console.log("------------------------");
        }
    }
}
