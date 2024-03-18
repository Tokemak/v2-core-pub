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
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { LMPStrategyTestHelpers as stratHelpers } from "test/strategy/LMPStrategyTestHelpers.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";

contract LensTest is BaseTest {
    Lens private lens;

    TestDestinationVault private defaultDestinationVault;

    function setUp() public virtual override {
        vm.warp(1000 days);

        super._setUp(false);

        address underlyer = address(BaseTest.mockAsset("underlyer", "underlyer", 0));
        testIncentiveCalculator = new TestIncentiveCalculator();
        testIncentiveCalculator.setLpToken(underlyer);

        // Destination Template Registry
        bytes32 dvType = keccak256(abi.encode("test"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        TestDestinationVault dv = new TestDestinationVault(systemRegistry);
        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        DestinationRegistry destinationTemplateRegistry = new DestinationRegistry(systemRegistry);
        destinationTemplateRegistry.addToWhitelist(dvTypes);
        destinationTemplateRegistry.register(dvTypes, dvs);
        systemRegistry.setDestinationTemplateRegistry(address(destinationTemplateRegistry));

        // Destination Vault Registry
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        // Destination Vault Factory
        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);
        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        // Default destination
        defaultDestinationVault = TestDestinationVault(
            destinationVaultFactory.create(
                "test",
                address(baseAsset),
                underlyer,
                address(testIncentiveCalculator),
                new address[](0),
                keccak256("salt1"),
                abi.encode("")
            )
        );

        bytes memory initData = abi.encode("");
        LMPStrategy stratTemplate = new LMPStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        lmpVaultFactory.addStrategyTemplate(address(stratTemplate));

        LMPVault lmpVault =
            LMPVault(lmpVaultFactory.createVault(address(stratTemplate), "x", "y", keccak256("v8"), initData));

        accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, address(this));

        address[] memory destinations = new address[](1);
        destinations[0] = address(defaultDestinationVault);
        lmpVault.addDestinations(destinations);

        lmpVaultRegistry = new LMPVaultRegistry(systemRegistry);
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));

        lmpVaultRegistry.addVault(address(lmpVault));

        lens = new Lens(systemRegistry);
    }

    function testLens() public {
        (ILens.LMPVault[] memory lmpVaults) = lens.getVaults();
        assertFalse(lmpVaults[0].vaultAddress == address(0));
        assertEq(lmpVaults[0].name, "y");
        assertEq(lmpVaults[0].symbol, "x");

        // Destination Vaults

        (address[] memory lmpVaults2, ILens.DestinationVault[][] memory destinations) = lens.getVaultDestinations();
        assertEq(lmpVaults[0].vaultAddress, lmpVaults2[0]);
        assertEq(lmpVaults[0].symbol, "x");
        assertFalse(destinations[0][0].vaultAddress == address(0));
        assertEq(destinations[0][0].exchangeName, "test");

        // Destination Tokens

        (address[] memory destinations2, ILens.UnderlyingToken[][] memory tokens) = lens.getVaultDestinationTokens();
        assertEq(destinations2[0], destinations[0][0].vaultAddress);
        assertEq(tokens[0][0].symbol, "underlyer");
        assertFalse(tokens[0][0].tokenAddress == address(0));

        // Destination Stats
        // (Data defined in the mock TestDestinationVault.sol contract.)

        (address[] memory destinations3, ILens.DestinationStats[] memory stats) = lens.getVaultDestinationStats();
        assertEq(destinations3[0], destinations[0][0].vaultAddress);
        assertEq(stats[0].lastSnapshotTimestamp, 1);
        assertEq(stats[0].feeApr, 2);
        assertEq(stats[0].reservesInEth[0], 3);

        ILSTStats.LSTStatsData memory lstStatsData = stats[0].lstStatsData[0];
        assertEq(lstStatsData.lastSnapshotTimestamp, 1);
        assertEq(lstStatsData.baseApr, 2);
        assertEq(lstStatsData.discount, 3);
        assertEq(lstStatsData.discountHistory[0], 4);
        assertEq(lstStatsData.discountTimestampByPercent[0], 5);
        assertEq(lstStatsData.slashingCosts[0], 6);
        assertEq(lstStatsData.slashingTimestamps[0], 7);

        IDexLSTStats.StakingIncentiveStats memory incentiveStats = stats[0].stakingIncentiveStats;
        assertEq(incentiveStats.safeTotalSupply, 1);
        assertEq(incentiveStats.rewardTokens[0], address(2));
        assertEq(incentiveStats.annualizedRewardAmounts[0], 3);
        assertEq(incentiveStats.periodFinishForRewards[0], 4);
        assertEq(incentiveStats.incentiveCredits, 5);
    }
}
