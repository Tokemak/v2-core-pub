// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseTest } from "test/BaseTest.t.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
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
        testIncentiveCalculator = new TestIncentiveCalculator(underlyer);
        defaultDestinationVault = new TestDestinationVault(
            systemRegistry, vm.addr(3434), address(baseAsset), underlyer, address(testIncentiveCalculator)
        );
        address[] memory destinations = new address[](1);
        destinations[0] = address(defaultDestinationVault);

        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);

        systemRegistry.setDestinationTemplateRegistry(address(destinationVaultRegistry));
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);

        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        vm.prank(address(destinationVaultFactory));
        destinationVaultRegistry.register(destinations[0]);

        bytes memory initData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: vm.addr(10_001) }));

        LMPVault lmpVault = LMPVault(
            lmpVaultFactory.createVault(type(uint112).max, type(uint112).max, "x", "y", keccak256("v8"), initData)
        );

        accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, address(this));
        lmpVault.addDestinations(destinations);

        lmpVaultRegistry = new LMPVaultRegistry(systemRegistry);
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));

        lmpVaultRegistry.addVault(address(lmpVault));

        lens = new Lens(systemRegistry);
    }

    function testLens() public {
        (ILens.LMPVault[] memory lmpVaults) = lens.getVaults();
        assertFalse(lmpVaults[0].vaultAddress == address(0));
        assertEq(lmpVaults[0].name, "y Pool Token");
        assertEq(lmpVaults[0].symbol, "lmpx");

        (address[] memory lmpVaults2, ILens.DestinationVault[][] memory destinations) = lens.getVaultDestinations();
        assertEq(lmpVaults[0].vaultAddress, lmpVaults2[0]);
        assertEq(lmpVaults[0].symbol, "lmpx");
        assertFalse(destinations[0][0].vaultAddress == address(0));
        assertEq(destinations[0][0].exchangeName, "test");

        (address[] memory destinations2, ILens.UnderlyingToken[][] memory tokens) = lens.getVaultDestinationTokens();
        assertEq(destinations2[0], destinations[0][0].vaultAddress);
        assertEq(tokens[0][0].symbol, "underlyer");
        assertFalse(tokens[0][0].tokenAddress == address(0));
    }
}
