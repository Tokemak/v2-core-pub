// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Lens } from "src/lens/Lens.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ILens } from "src/interfaces/lens/ILens.sol";

contract LensInt is Test {
    address public constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    Lens internal _lens;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_321_885);
        vm.selectFork(forkId);

        _lens = new Lens(ISystemRegistry(SYSTEM_REGISTRY));
    }

    function test_ReturnsVaults() public {
        // Should only have one deployed at this block

        ILens.LMPVault[] memory vaults = _lens.getVaults();

        assertEq(vaults.length, 1, "len");
        assertEq(vaults[0].vaultAddress, 0xA43a16d818Fea4Ad0Fb9356D33904251d726079b, "addr");
    }

    function test_ReturnsDestinations() public {
        (address[] memory lmpVaults, ILens.DestinationVault[][] memory destinations) = _lens.getVaultDestinations();

        assertEq(lmpVaults.length, 1, "vaultLen");
        assertEq(destinations.length, 1, "destLen");
        assertEq(destinations[0].length, 2, "vaultDestLen");
    }
}
