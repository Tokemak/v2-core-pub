// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { Roles } from "src/libs/Roles.sol";

contract AddDestinationsToPool is Script {
    address public autoPool = 0x49C4719EaCc746b87703F964F09C22751F397BA0;

    Constants.Values public constants;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        AutopoolETH autopool = AutopoolETH(autoPool);

        address[] memory destinations = new address[](16);
        destinations[0] = 0x8C598Be7D29ca09d847275356E1184F166B96931;
        destinations[1] = 0x9CA9B5dB35e5a48f2B147DaBB8e9848475094669;
        destinations[2] = 0x8A580F95bF9478C9EC9166E70F5bf2d489C15d8f;
        destinations[3] = 0x1E02da6E4DFc4875E372104E5e79d54632F52cB3;
        destinations[4] = 0x5817Cc19A51F92a1fc2806C0228b323fa5be72a0;
        destinations[5] = 0x0D883F9600857a28CfBccb16b10095EAcF8055af;
        destinations[6] = 0xb2f0d11Ce7D12CdA959775A1D9a608eA21123c9A;
        destinations[7] = 0x9F4d181F42c06949E4A256EEB4AeFa841371F624;
        destinations[8] = 0xE9D758002676EecCfAc6106c1E31fE04e419c01D;
        destinations[9] = 0xa3956D49106288E5c04E6FBbBad5b68593f0bE3b;
        destinations[10] = 0xF35fbb601e7de870029691f1872D67A8fC866B15;
        destinations[11] = 0xA6B62bFdc664Af24DDdfF335A167b867f1d590aF;
        destinations[12] = 0x0b08E02644745e26963c95935A1da19d8D927b97;
        destinations[13] = 0x37e565f997c2b16d2542E906672E9c6281e77954;
        destinations[14] = 0x1568528A93393B8dfc708f3FD0537C549290AC73;
        destinations[15] = 0x2E5A8C3aE475734Ece6443B5E68F7fA63133AF3D;

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);
        autopool.removeDestinations(destinations);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        vm.stopBroadcast();
    }
}
