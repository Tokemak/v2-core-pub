// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";

contract ConfigAutopools is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        address[] memory autoEthDestinations = new address[](13);
        autoEthDestinations[0] = 0xf3ae3c74EaD129e770A864CeE291A805b170bBe0;
        autoEthDestinations[1] = 0x865e59D439BF7310c9BC6117E6020B8C87De4065;
        autoEthDestinations[2] = 0x25cb41919d6B88e0D48108A4F5fe8FBb3744aFE1;
        autoEthDestinations[3] = 0x6DcB6797b1C0442587c2ad79745ef7BB487Fc2E2;
        autoEthDestinations[4] = 0xe3AE2Ab9AE8ADe1B4940dd893C9339401bEe61A1;
        autoEthDestinations[5] = 0xfB6f99FdF12E37Bfe3c4Cf81067faB10c465fb24;
        autoEthDestinations[6] = 0x896eCc16Ab4AFfF6cE0765A5B924BaECd7Fa455a;
        autoEthDestinations[7] = 0xC001f23397dB71B17602Ce7D90a983Edc38DB0d1;
        autoEthDestinations[8] = 0x6a8C6ff78082a2ae494EB9291DdC7254117298Ff;
        autoEthDestinations[9] = 0x8cA2201BC34780f14Bca452913ecAc8e9928d4cA;
        autoEthDestinations[10] = 0xd96E943098B2AE81155e98D7DC8BeaB34C539f01;
        autoEthDestinations[11] = 0xE382BBd32C4E202185762eA433278f4ED9E6151E;
        autoEthDestinations[12] = 0x87F46aa699840705F587761d9cfF290fCe1F84aE;

        address[] memory autoLrtDestinations = new address[](6);
        autoLrtDestinations[0] = 0xC4c973eDC82CB6b972C555672B4e63713C177995;
        autoLrtDestinations[1] = 0x148Ca723BefeA7b021C399413b8b7426A4701500;
        autoLrtDestinations[2] = 0x90300b02b162F902B9629963830BcCCdeEd71113;
        autoLrtDestinations[3] = 0x4E12227b350E8f8fEEc41A58D36cE2fB2e2d4575;
        autoLrtDestinations[4] = 0x2F7e096a400ded5D02762120b39A3aA4ABA072a4;
        autoLrtDestinations[5] = 0x777FAf85c8E5FC6f4332E56B989C5C94201A273C;

        address[] memory balEthDestinations = new address[](12);
        balEthDestinations[0] = 0xf3ae3c74EaD129e770A864CeE291A805b170bBe0;
        balEthDestinations[1] = 0x865e59D439BF7310c9BC6117E6020B8C87De4065;
        balEthDestinations[2] = 0x25cb41919d6B88e0D48108A4F5fe8FBb3744aFE1;
        balEthDestinations[3] = 0x6DcB6797b1C0442587c2ad79745ef7BB487Fc2E2;
        balEthDestinations[4] = 0xe3AE2Ab9AE8ADe1B4940dd893C9339401bEe61A1;
        balEthDestinations[5] = 0xfB6f99FdF12E37Bfe3c4Cf81067faB10c465fb24;
        balEthDestinations[6] = 0xC4c973eDC82CB6b972C555672B4e63713C177995;
        balEthDestinations[7] = 0x148Ca723BefeA7b021C399413b8b7426A4701500;
        balEthDestinations[8] = 0x90300b02b162F902B9629963830BcCCdeEd71113;
        balEthDestinations[9] = 0x4E12227b350E8f8fEEc41A58D36cE2fB2e2d4575;
        balEthDestinations[10] = 0x2F7e096a400ded5D02762120b39A3aA4ABA072a4;
        balEthDestinations[11] = 0x8cA2201BC34780f14Bca452913ecAc8e9928d4cA;

        constants.sys.accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);

        AutopoolETH(0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56).addDestinations(autoEthDestinations);
        AutopoolETH(0xE800e3760FC20aA98c5df6A9816147f190455AF3).addDestinations(autoLrtDestinations);
        AutopoolETH(0x6dC3ce9C57b20131347FDc9089D740DAf6eB34c5).addDestinations(balEthDestinations);

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_DESTINATION_UPDATER, owner);
    }
}
