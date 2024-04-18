// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { EethOracle } from "src/oracles/providers/EethOracle.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { EETH_MAINNET, WEETH_MAINNET } from "test/utils/Addresses.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract EethOracleTests is Test {
    address internal constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;
    address internal constant OWNER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address internal constant REDSTONE_ORACLE = 0x9E16879c6F4415Ce5EBE21816C51F476AEEc49bE;

    address private weETH;
    address private eETH;
    RootPriceOracle private _rootPriceOracle;
    ISystemRegistry private _systemRegistry;
    RedstoneOracle private _redstoneOracle;
    EethOracle private _oracle;

    function test_getPriceInEth_CalculatesCorrectly() public {
        // Prices
        // ETH $3062.62
        // weETH $3,171.27
        // eETH $3,072.82

        _setUp(19_683_316);

        uint256 eETHPrice = _rootPriceOracle.getPriceInEth(EETH_MAINNET);
        uint256 weETHprice = _rootPriceOracle.getPriceInEth(WEETH_MAINNET);

        assertApproxEqAbs(eETHPrice, 1e18, 0.01e18);
        assertTrue(eETHPrice < weETHprice, "lt");
    }

    function test_getPriceInEth_CalculatesCorrectlyPast() public {
        // Prices
        // ETH $2954.62
        // weETH $3054.37
        // eETH $2944.05

        _setUp(19_676_541);

        uint256 eETHPrice = _rootPriceOracle.getPriceInEth(EETH_MAINNET);
        uint256 weETHprice = _rootPriceOracle.getPriceInEth(WEETH_MAINNET);

        assertApproxEqAbs(eETHPrice, 0.996422552e18, 0.01e18);
        assertTrue(eETHPrice < weETHprice, "lt");
    }

    function _setUp(uint256 blockNumber) internal {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
        vm.selectFork(mainnetFork);

        _systemRegistry = ISystemRegistry(SYSTEM_REGISTRY);
        _rootPriceOracle = RootPriceOracle(address(_systemRegistry.rootPriceOracle()));
        _redstoneOracle = RedstoneOracle(REDSTONE_ORACLE);

        vm.startPrank(OWNER);
        _redstoneOracle.registerOracle(
            WEETH_MAINNET,
            IAggregatorV3Interface(0x8751F736E94F6CD167e8C5B97E245680FbD9CC36),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        _oracle = EethOracle(Clones.clone(address(new EethOracle(_systemRegistry, WEETH_MAINNET))));

        _rootPriceOracle.registerMapping(WEETH_MAINNET, _redstoneOracle);
        _rootPriceOracle.registerMapping(EETH_MAINNET, _oracle);
        vm.stopPrank();
    }
}
