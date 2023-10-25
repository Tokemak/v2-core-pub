// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { FrxBeaconChainBacking } from "src/beacon/FrxBeaconChainBacking.sol";
import { IBeaconChainBacking } from "src/interfaces/beacon/IBeaconChainBacking.sol";
import { PRANK_ADDRESS, RANDOM, TOKE_MAINNET, WETH_MAINNET, FRXETH_MAINNET } from "test/utils/Addresses.sol";

import { BaseTest } from "test/BaseTest.t.sol";

contract FrxBeaconChainBackingTest is Test {
    AccessController private accessController;
    FrxBeaconChainBacking private beaconBacking;

    event RatioUpdated(uint208 ratio, uint208 totalAssets, uint208 totalLiabilities, uint48 timestamp);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.label(address(this), "testContract");

        SystemRegistry systemRegistry = new SystemRegistry(vm.addr(100), WETH_MAINNET);

        accessController = new AccessController(address(systemRegistry));
        accessController.grantRole(Roles.LSD_BACKING_UPDATER, address(this));

        systemRegistry.setAccessController(address(accessController));

        beaconBacking = new FrxBeaconChainBacking(systemRegistry, FRXETH_MAINNET);
    }

    function testUpdateRatio() public {
        uint208 totalAssets = 90;
        uint208 totalLiabilities = 10;
        uint48 queriedTimestamp = 999;

        uint208 expectedRatio = 9_000_000_000_000_000_000;

        vm.expectEmit(true, true, true, true);
        emit RatioUpdated(expectedRatio, totalAssets, totalLiabilities, queriedTimestamp);

        beaconBacking.update(totalAssets, totalLiabilities, queriedTimestamp);

        (uint208 ratio, uint48 timestamp) = beaconBacking.current();

        assertEq(expectedRatio, ratio);
        assertEq(queriedTimestamp, timestamp);
    }

    function testRevertOnUpdateRatioWithoutRole() public {
        accessController.revokeRole(Roles.LSD_BACKING_UPDATER, address(this));

        uint208 totalAssets = 90;
        uint208 totalLiabilities = 10;
        uint48 queriedTimestamp = 999;

        vm.expectRevert();
        beaconBacking.update(totalAssets, totalLiabilities, queriedTimestamp);
    }

    function testUpdateRatioWhenTotalAssetsIsZero() public {
        uint208 totalAssets = 0;
        uint208 totalLiabilities = 10;
        uint48 queriedTimestamp = 999;
        uint208 expectedRatio = 0;

        _runRatioTest(totalAssets, totalLiabilities, queriedTimestamp, expectedRatio);
    }

    function testUpdateRatioWhenTotalLiabilitiesIsZero() public {
        uint208 totalAssets = 10;
        uint208 totalLiabilities = 0;
        uint48 queriedTimestamp = 999;
        uint208 expectedRatio = 1e18;

        _runRatioTest(totalAssets, totalLiabilities, queriedTimestamp, expectedRatio);
    }

    function testUpdateRatioWhenBothTotalAssetsAndTotalLiabilitiesAreZero() public {
        uint208 totalAssets = 0;
        uint208 totalLiabilities = 0;
        uint48 queriedTimestamp = 999;
        uint208 expectedRatio = 1e18;

        _runRatioTest(totalAssets, totalLiabilities, queriedTimestamp, expectedRatio);
    }

    function _runRatioTest(
        uint208 totalAssets,
        uint208 totalLiabilities,
        uint48 queriedTimestamp,
        uint208 expectedRatio
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit RatioUpdated(expectedRatio, totalAssets, totalLiabilities, queriedTimestamp);
        beaconBacking.update(totalAssets, totalLiabilities, queriedTimestamp);

        (uint208 ratio, uint48 timestamp) = beaconBacking.current();
        assertEq(expectedRatio, ratio);
        assertEq(queriedTimestamp, timestamp);
    }

    function testRevertOnUpdateRatioWhenTimestampIsLessThanCurrent() public {
        uint208 totalAssets = 90;
        uint208 totalLiabilities = 10;
        uint48 queriedTimestamp = 999;

        beaconBacking.update(totalAssets, totalLiabilities, queriedTimestamp);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "queriedTimestamp"));
        beaconBacking.update(totalAssets, totalLiabilities, queriedTimestamp - 1);
    }
}
