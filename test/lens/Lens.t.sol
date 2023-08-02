// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseTest } from "test/BaseTest.t.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
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

        address baseAsset = address(new TestERC20("baseAsset", "baseAsset"));
        address underlyer = address(new TestERC20("underlyer", "underlyer"));
        testDestinationVault = new TestDestinationVault(systemRegistry,vm.addr(34343), baseAsset, underlyer);
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
        ILens.LMPVault[] memory lmpVaults = lens.getVaults();
        assertEq(lmpVaults[0].name, "y Pool Token");
        assertEq(lmpVaults[0].symbol, "lmpx");
        assertFalse(lmpVaults[0].vaultAddress == address(0));

        ILens.DestinationVault[] memory destinations = lens.getDestinations(lmpVaults[0].vaultAddress);
        assertEq(destinations[0].exchangeName, "test");
        assertFalse(destinations[0].vaultAddress == address(0));

        ILens.UnderlyingToken[] memory underlyingTokens = lens.getUnderlyingTokens(destinations[0].vaultAddress);
        assertEq(underlyingTokens[0].symbol, "underlyer");
        assertFalse(underlyingTokens[0].tokenAddress == address(0));
    }
}
