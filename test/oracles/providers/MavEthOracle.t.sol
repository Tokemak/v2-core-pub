// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import {
    WETH9_ADDRESS,
    TOKE_MAINNET,
    WSTETH_MAINNET,
    MAV_WSTETH_WETH_BOOSTED_POS,
    MAV_WSTETH_WETH_POOL,
    MAV_POOL_INFORMATION,
    WETH_MAINNET
} from "test/utils/Addresses.sol";

import { MavEthOracle } from "src/oracles/providers/MavEthOracle.sol";
import { SystemRegistry, ISystemRegistry } from "src/SystemRegistry.sol";
import { AccessController, IAccessController } from "src/security/AccessController.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { Errors } from "src/utils/Errors.sol";

// solhint-disable func-name-mixedcase

contract MavEthOracleTest is Test {
    event MaxTotalBinWidthSet(uint256 newMaxBinWidth);
    event PoolInformationSet(address poolInformation);

    SystemRegistry public registry;
    AccessController public accessControl;
    RootPriceOracle public rootOracle;
    MavEthOracle public mavOracle;

    function setUp() external {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 18_579_296);
        vm.selectFork(mainnetFork);

        registry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        accessControl = new AccessController(address(registry));
        registry.setAccessController(address(accessControl));
        rootOracle = new RootPriceOracle(registry);
        registry.setRootPriceOracle(address(rootOracle));
        mavOracle = new MavEthOracle(registry, MAV_POOL_INFORMATION);
    }

    // Constructor tests
    function test_RevertSystemRegistryZeroAddress() external {
        // Reverts with generic evm revert.
        vm.expectRevert();
        new MavEthOracle(ISystemRegistry(address(0)), MAV_POOL_INFORMATION);
    }

    function test_RevertPoolInformationZeroAddress() external {
        // Reverts with generic evm revert.
        vm.expectRevert();
        new MavEthOracle(registry, address(0));
    }

    function test_RevertRootPriceOracleZeroAddress() external {
        // Doesn't have root oracle set.
        SystemRegistry localSystemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        AccessController localAccessControl = new AccessController(address(localSystemRegistry));
        localSystemRegistry.setAccessController(address(localAccessControl));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "priceOracle"));
        new MavEthOracle(ISystemRegistry(address(localSystemRegistry)), MAV_POOL_INFORMATION);
    }

    function test_ProperlySetsState() external {
        assertEq(mavOracle.getSystemRegistry(), address(registry));
    }

    // Test setMaxTotalBinWidth
    function test_OnlyOwner() external {
        vm.prank(address(1));
        vm.expectRevert(IAccessController.AccessDenied.selector);

        mavOracle.setMaxTotalBinWidth(60);
    }

    function test_RevertZero() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "_maxTotalbinWidth"));

        mavOracle.setMaxTotalBinWidth(0);
    }

    function test_ProperlySetsMax() external {
        vm.expectEmit(false, false, false, true);
        emit MaxTotalBinWidthSet(60);

        mavOracle.setMaxTotalBinWidth(60);
        assertEq(mavOracle.maxTotalBinWidth(), 60);
    }

    // Test getPriceInEth
    function test_RevertZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_boostedPosition"));

        mavOracle.getPriceInEth(address(0));
    }

    // Test setPoolInformation error case
    function test_SetPoolInformation_RevertIf_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_poolInformation"));
        mavOracle.setPoolInformation(address(0));
    }

    // Test setPoolInformation event
    function test_SetPoolInformation_Emits_PoolInformationSetEvent() external {
        vm.expectEmit(false, false, false, true);
        emit PoolInformationSet(MAV_POOL_INFORMATION);

        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);
    }

    // Test setPoolInformation state
    function test_SetPoolInformation() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        assertEq(address(mavOracle.poolInformation()), MAV_POOL_INFORMATION);
    }

    // Test getSpotPrice error case
    function test_GetSpotPrice_RevertIf_PoolZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "poolAddress"));
        mavOracle.getSpotPrice(WSTETH_MAINNET, address(0), WETH_MAINNET);
    }

    function test_GetSpotPrice_RevertIf_InvalidToken() external {
        vm.expectRevert(abi.encodeWithSelector(MavEthOracle.InvalidToken.selector));
        mavOracle.getSpotPrice(address(0), MAV_WSTETH_WETH_POOL, WETH_MAINNET);
    }

    /// @dev WestEth -> Weth at block 18_579_296 is 1.146037501992223339
    function test_GetSpotPrice_WstEthWeth() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (uint256 price,) = mavOracle.getSpotPrice(WSTETH_MAINNET, MAV_WSTETH_WETH_POOL, WETH_MAINNET);

        assertEq(price, 1_146_037_501_992_223_339);
    }

    /// @dev Weth -> WestEth at block 18_579_296 is 0.872571401184986273
    function test_GetSpotPrice_WethWstEth() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (uint256 price,) = mavOracle.getSpotPrice(WETH_MAINNET, MAV_WSTETH_WETH_POOL, WSTETH_MAINNET);

        assertEq(price, 872_571_401_184_986_273);
    }

    function test_GetSpotPrice_ReturnActualQuoteToken() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (, address actualQuoteToken) = mavOracle.getSpotPrice(WETH_MAINNET, MAV_WSTETH_WETH_POOL, address(0));

        // Asking for Weth -> address(0), so should return wsEth.
        assertEq(actualQuoteToken, WSTETH_MAINNET);
    }
}

contract GetSafeSpotPriceInfo is MavEthOracleTest {
    function test_NotImplemented() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotImplemented.selector));
        // solhint-disable-next-line no-unused-vars
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            mavOracle.getSafeSpotPriceInfo(MAV_WSTETH_WETH_POOL, MAV_WSTETH_WETH_BOOSTED_POS, WETH_MAINNET);
    }
}
