// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { IAutoPxEth } from "src/interfaces/external/pirex/IAutoPxEth.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { PxETHEthOracle } from "src/oracles/providers/PxETHEthOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import {
    TOKE_MAINNET,
    WETH9_ADDRESS,
    PXETH_MAINNET,
    APXETH_MAINNET,
    APXETH_RS_FEED_MAINNET
} from "test/utils/Addresses.sol";

contract PxETHEthOracleTests is Test {
    RootPriceOracle public rootPriceOracle;
    SystemRegistry public systemRegistry;
    PxETHEthOracle public oracle;
    IAutoPxEth public apxETH;
    RedstoneOracle public apxETHRedstoneOracle;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_678_792);
        vm.selectFork(mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        AccessController accessControl = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessControl));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        oracle = new PxETHEthOracle(systemRegistry, APXETH_MAINNET, PXETH_MAINNET);
        apxETH = IAutoPxEth(APXETH_MAINNET);
        apxETHRedstoneOracle = new RedstoneOracle(systemRegistry);

        accessControl.grantRole(Roles.ORACLE_MANAGER, address(this));
        apxETHRedstoneOracle.registerOracle(
            APXETH_MAINNET,
            IAggregatorV3Interface(APXETH_RS_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        rootPriceOracle.registerMapping(address(apxETH), apxETHRedstoneOracle);
    }

    //Constructor Tests
    function test_RevertSystemRegistryZeroAddress() public {
        vm.expectRevert();
        oracle = new PxETHEthOracle(ISystemRegistry(address(0)), APXETH_MAINNET, PXETH_MAINNET);
    }

    function test_RevertApxEthZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_apxETH"));
        oracle = new PxETHEthOracle(systemRegistry, address(0), PXETH_MAINNET);
    }

    function test_RevertPxEthZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_pxETH"));
        oracle = new PxETHEthOracle(systemRegistry, APXETH_MAINNET, address(0));
    }

    function test_RevertInvalidPxEthAsset() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAddress.selector, address(1)));
        oracle = new PxETHEthOracle(systemRegistry, APXETH_MAINNET, address(1));
    }

    function test_ApxEthAsset() public {
        assertEq(apxETH.asset(), PXETH_MAINNET);
    }
}

contract GetPriceInEth is PxETHEthOracleTests {
    function testBasicPriceAA() public {
        uint256 expectedPrice = 997_730_624_760_204_850;
        uint256 price = oracle.getPriceInEth(apxETH.asset());
        assertApproxEqAbs(price, expectedPrice, 1e17);
    }

    function testInvalidToken() public {
        address fakeAddr = vm.addr(34_343);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, fakeAddr));
        oracle.getPriceInEth(address(fakeAddr));
    }
}
