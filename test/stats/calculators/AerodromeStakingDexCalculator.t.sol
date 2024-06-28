// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { AerodromeStakingDexCalculator } from "src/stats/calculators/AerodromeStakingDexCalculator.sol";
import { WETH9_BASE, RETH_BASE } from "test/utils/Addresses.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IPool } from "src/interfaces/external/aerodrome/IPool.sol";
import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";

contract AerodromeStakingDexCalculatorTest is Test {
    uint256 private constant TARGET_BLOCK = 13_719_843;
    AerodromeStakingDexCalculator private calculator;

    address private mockToke = vm.addr(22);
    address private pool = vm.addr(33);

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RootPriceOracle private rootPriceOracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), TARGET_BLOCK);

        systemRegistry = new SystemRegistry(mockToke, WETH9_BASE);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));

        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        // Note the current LST calculators won't work because rETH does not have a .exchangeRate() function
        // so you can't use rETH as is
        // use Stats.NOOP_APR_ID instead

        vm.mockCall(pool, abi.encodeWithSelector(IPool.token0.selector), abi.encode(WETH9_BASE));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.token1.selector), abi.encode(RETH_BASE));
        // mock pool is (WETH, rETH)
        calculator =
            AerodromeStakingDexCalculator(Clones.clone(address(new AerodromeStakingDexCalculator(systemRegistry))));
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function successfulInitalize() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;
        bytes memory initData = abi.encode(AerodromeStakingDexCalculator.InitData({ poolAddress: address(pool) }));
        calculator.initialize(depAprIds, initData);
    }

    function testSuccessfulInitalize() public {
        successfulInitalize();

        assertEq(calculator.getAddressId(), pool);
        assertEq(calculator.reserveTokens(0), address(WETH9_BASE));
        assertEq(calculator.reserveTokens(1), address(RETH_BASE));
        assertEq(calculator.reserveTokensDecimals(0), 18);
        assertEq(calculator.reserveTokensDecimals(1), 18);
        assertEq(address(calculator.lstStats(0)), address(0));
        assertEq(address(calculator.lstStats(1)), address(0));
    }

    function testCurrent() public {
        // TODO add tests for when we have LST calculators that can work on Base

        successfulInitalize();
        assertFalse(calculator.shouldSnapshot());

        vm.mockCall(pool, abi.encodeWithSelector(IPool.reserve0.selector), abi.encode(100e18));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.reserve1.selector), abi.encode(99e18));

        mockTokenPrice(WETH9_BASE, 1e18);
        mockTokenPrice(RETH_BASE, 2e18);

        IDexLSTStats.DexLSTStatsData memory data = calculator.current();

        assertEq(data.lastSnapshotTimestamp, block.timestamp);
        assertEq(data.feeApr, 0);
        assertEq(data.reservesInEth[0], 100e18);
        assertEq(data.reservesInEth[1], 198e18);

        assertFalse(calculator.shouldSnapshot());
    }
}
