// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerMetaStablePoolCalculator } from "src/stats/calculators/BalancerMetaStablePoolCalculator.sol";
import { BAL_VAULT, TOKE_MAINNET, WETH_MAINNET, RETH_MAINNET, RETH_WETH_BAL_POOL } from "test/utils/Addresses.sol";

contract BalancerMetaStablePoolCalculatorTest is Test {
    TestBalancerCalculator private calculator;

    function testGetPoolTokens() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_735_327);

        prepare();

        (IERC20[] memory assets, uint256[] memory balances) = calculator.verifyGetPoolTokens();

        // Verify assets
        assertEq(assets.length, 2);
        assertEq(address(assets[0]), RETH_MAINNET);
        assertEq(address(assets[1]), WETH_MAINNET);

        // Verify balances
        assertEq(balances.length, 2);
        assertEq(balances[0], 14_836_292_543_788_043_984_318);
        assertEq(balances[1], 19_048_677_532_458_348_397_401);
    }

    function testGetVirtualPrice() public {
        checkVirtualPrice(17_272_708, 1_022_381_861_209_653_267);
        checkVirtualPrice(17_279_454, 1_022_408_403_239_548_106);
        checkVirtualPrice(17_286_461, 1_022_459_156_385_702_926);
        checkVirtualPrice(17_293_521, 1_022_507_305_450_043_174);
        checkVirtualPrice(17_393_019, 1_022_900_945_513_491_754);
    }

    function checkVirtualPrice(uint256 targetBlock, uint256 expected) private {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), targetBlock);

        prepare();

        assertEq(calculator.verifyGetVirtualPrice(), expected);
    }

    function prepare() private {
        // System setup
        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));

        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));

        StatsCalculatorRegistry statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        StatsCalculatorFactory statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        // Calculator setup
        calculator = new TestBalancerCalculator(systemRegistry, BAL_VAULT);

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;

        calculator.initialize(
            depAprIds, abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: RETH_WETH_BAL_POOL }))
        );
    }
}

contract TestBalancerCalculator is BalancerMetaStablePoolCalculator {
    constructor(
        ISystemRegistry _systemRegistry,
        address vault
    ) BalancerMetaStablePoolCalculator(_systemRegistry, vault) { }

    function verifyGetVirtualPrice() public view returns (uint256) {
        return getVirtualPrice();
    }

    function verifyGetPoolTokens() public view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return getPoolTokens();
    }
}
