// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseTest } from "test/BaseTest.t.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";
import { Roles } from "src/libs/Roles.sol";
import { Lens } from "src/lens/Lens.sol";
import { ILens } from "src/interfaces/lens/ILens.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";

contract LensTest is BaseTest {
    Lens private lens;

    function setUp() public virtual override {
        super._setUp(false);

        address underlyer = address(BaseTest.mockAsset("underlyer", "underlyer", 0));

        testDestinationVault = new TestDestinationVault(systemRegistry,vm.addr(34343), address(baseAsset), underlyer);
        address[] memory destinations = new address[](1);
        destinations[0] = address(testDestinationVault);

        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);

        systemRegistry.setDestinationTemplateRegistry(address(destinationVaultRegistry));
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);

        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        vm.prank(address(destinationVaultFactory));
        destinationVaultRegistry.register(destinations[0]);

        LMPVault lmpVault =
            LMPVault(lmpVaultFactory.createVault(type(uint256).max, type(uint256).max, "x", "y", keccak256("v8"), ""));

        accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, address(this));
        lmpVault.addDestinations(destinations);

        lmpVaultRegistry = new LMPVaultRegistry(systemRegistry);
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));

        lmpVaultRegistry.addVault(address(lmpVault));

        lens = new Lens(systemRegistry);
    }

    function testLens() public {
        (ILens.LMPVault[] memory lmpVaults, address[] memory lmpAddresses) = lens.getVaults();
        assertEq(lmpVaults[0].name, "y Pool Token");
        assertEq(lmpVaults[0].symbol, "lmpx");
        assertFalse(lmpAddresses[0] == address(0));

        (ILens.DestinationVault[] memory destinations, address[] memory destinationAddresses) =
            lens.getDestinations(lmpAddresses[0]);
        assertEq(destinations[0].exchangeName, "test");
        assertFalse(destinationAddresses[0] == address(0));

        ILens.UnderlyingToken[] memory underlyingTokens = lens.getUnderlyingTokens(destinationAddresses[0]);
        assertEq(underlyingTokens[0].symbol, "underlyer");
        assertFalse(underlyingTokens[0].tokenAddress == address(0));
    }
}
