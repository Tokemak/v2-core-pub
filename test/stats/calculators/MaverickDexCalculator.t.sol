// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Stats } from "src/stats/Stats.sol";
import { Roles } from "src/libs/Roles.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MaverickDexCalculator } from "src/stats/calculators/MaverickDexCalculator.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { RethLSTCalculator } from "src/stats/calculators/RethLSTCalculator.sol";
import { SwethLSTCalculator } from "src/stats/calculators/SwethLSTCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { MaverickFeeAprOracle } from "src/oracles/providers/MaverickFeeAprOracle.sol";
import { IMaverickFeeAprOracle } from "src/interfaces/oracles/IMaverickFeeAprOracle.sol";
import { IPoolPositionSlim } from "src/interfaces/external/maverick/IPoolPositionSlim.sol";
import { Stats } from "src/stats/Stats.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { TOKE_MAINNET, WETH_MAINNET, RETH_MAINNET, SWETH_MAINNET } from "test/utils/Addresses.sol";

//solhint-disable func-name-mixedcase

contract MaverickDexCalculatorTest is Test {
    uint256 private constant TARGET_BLOCK = 19_000_000;

    MaverickDexCalculator private calculator;

    address private constant WETH = WETH_MAINNET;

    address private pool = vm.addr(22);
    address private boostedPosition = vm.addr(33);

    address private lstCalc0 = vm.addr(2222);
    address private lstCalc1 = vm.addr(3333);

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RethLSTCalculator private rETHStats;
    RootPriceOracle private rootPriceOracle;
    MaverickFeeAprOracle private feeAprOracle;
    SwethLSTCalculator private swETHStats;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), TARGET_BLOCK);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));
        accessController.grantRole(Roles.STATS_CALC_REGISTRY_MANAGER, address(this));

        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        feeAprOracle = new MaverickFeeAprOracle(systemRegistry);

        mockTokenPrice(WETH, 1e18);

        rETHStats = RethLSTCalculator(Clones.clone(address(new RethLSTCalculator(systemRegistry))));
        bytes32[] memory rETHDepAprIds = new bytes32[](0);

        LSTCalculatorBase.InitData memory rETHInit = LSTCalculatorBase.InitData({ lstTokenAddress: RETH_MAINNET });
        mockTokenPrice(RETH_MAINNET, 1e18);
        rETHStats.initialize(rETHDepAprIds, abi.encode(rETHInit));
        vm.prank(address(statsFactory));
        statsRegistry.register(address(rETHStats));

        swETHStats = SwethLSTCalculator(Clones.clone(address(new SwethLSTCalculator(systemRegistry))));
        bytes32[] memory swETHDepAprIds = new bytes32[](0);

        LSTCalculatorBase.InitData memory swETHInit = LSTCalculatorBase.InitData({ lstTokenAddress: SWETH_MAINNET });
        mockTokenPrice(SWETH_MAINNET, 1e18);
        swETHStats.initialize(swETHDepAprIds, abi.encode(swETHInit));
        vm.prank(address(statsFactory));
        statsRegistry.register(address(swETHStats));
        vm.mockCall(boostedPosition, abi.encodeWithSelector(IPoolPositionSlim.pool.selector), abi.encode(pool));

        calculator = MaverickDexCalculator(Clones.clone(address(new MaverickDexCalculator(systemRegistry))));
    }

    function mockRethWethBoostedPostion() internal {
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(WETH));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = Stats.NOOP_APR_ID; // WETH

        mockPositionReserves(100e18, 100e18);
        calculator.initialize(depAprIds, abi.encode(initData));
    }

    function mockRethSWethBoostedPostion() internal {
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(SWETH_MAINNET));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = swETHStats.getAprId();

        mockPositionReserves(100e18, 100e18);
        calculator.initialize(depAprIds, abi.encode(initData));
    }

    function mockFeeApr(uint256 feeApr, uint256 timestamp) internal {
        vm.mockCall(
            address(feeAprOracle),
            abi.encodeWithSelector(IMaverickFeeAprOracle.getFeeApr.selector, address(calculator.boostedPosition())),
            abi.encode(feeApr, uint40(timestamp))
        );
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function mockPositionReserves(uint256 reserves0, uint256 reserves1) internal {
        vm.mockCall(
            boostedPosition,
            abi.encodeWithSelector(IPoolPositionSlim.getReserves.selector),
            abi.encode(reserves0, reserves1)
        );
    }

    function mockLSTData(address lstCalc, uint256 baseApr) internal {
        uint24[10] memory discountHistory;
        uint40 discountTimestampByPercent;
        ILSTStats.LSTStatsData memory res = ILSTStats.LSTStatsData({
            lastSnapshotTimestamp: 0,
            baseApr: baseApr,
            discount: 0,
            discountHistory: discountHistory,
            discountTimestampByPercent: discountTimestampByPercent
        });
        vm.mockCall(lstCalc, abi.encodeWithSelector(ILSTStats.current.selector), abi.encode(res));
    }

    function test_SingleLSTBoostedPositionInit() public {
        mockRethWethBoostedPostion();
        assertEq(calculator.reserveTokens(0), RETH_MAINNET);
        assertEq(calculator.reserveTokens(1), WETH);
    }

    function test_TwoLSTBoostedPositionInit() public {
        mockRethSWethBoostedPostion();
        assertEq(calculator.reserveTokens(0), RETH_MAINNET);
        assertEq(calculator.reserveTokens(1), SWETH_MAINNET);
    }

    function test_InititalizeRevertsIfBoostedPositionDoesNotMatchInitPool() public {
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(WETH));
        vm.mockCall(boostedPosition, abi.encodeWithSelector(IPoolPositionSlim.pool.selector), abi.encode(vm.addr(99)));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = Stats.NOOP_APR_ID;

        mockPositionReserves(100e18, 100e18);
        vm.expectRevert();
        calculator.initialize(depAprIds, abi.encode(initData));
    }

    function test_InitFailIfMismatchDependentAPRs() public {
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(WETH));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        // the order is switched so we expect it to revert
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = rETHStats.getAprId();

        mockPositionReserves(100e18, 100e18);
        vm.expectRevert();
        calculator.initialize(depAprIds, abi.encode(initData));
    }

    function test_InitFailIfZeroAddressAsToken() public {
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(address(0)));

        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenAScale.selector), abi.encode(18));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenBScale.selector), abi.encode(18));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = Stats.NOOP_APR_ID;

        mockPositionReserves(100e18, 100e18);
        vm.expectRevert();
        calculator.initialize(depAprIds, abi.encode(initData));
    }

    function test_shouldSnapshotTimeContraints() public {
        mockRethWethBoostedPostion();
        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();
        assertFalse(calculator.shouldSnapshot());
        vm.warp(block.timestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL);
        assertFalse(calculator.shouldSnapshot());
        vm.warp(block.timestamp + 1);
        assertTrue(calculator.shouldSnapshot());
        calculator.snapshot();
    }

    function test_SnapshotFailsIfFeeAprNotSet() public {
        mockRethWethBoostedPostion();
        assertTrue(calculator.shouldSnapshot());
        vm.expectRevert();
        calculator.snapshot();
        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();
    }

    function test_FirstSnapshot() public {
        mockRethSWethBoostedPostion();
        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();

        assertEq(calculator.reservesInEth(0), 100e18);
        assertEq(calculator.reservesInEth(1), 100e18);

        assertEq(calculator.feeApr(), 1e18);
        assertTrue(calculator.reservesInEthFilterInitialized());
        assertTrue(calculator.feeAprFilterInitialized());
    }

    function test_Current() public {
        mockRethSWethBoostedPostion();
        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();

        uint256 prevTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        mockLSTData(address(rETHStats), 4e18);
        mockLSTData(address(swETHStats), 3e18);

        IDexLSTStats.DexLSTStatsData memory cur = calculator.current();

        assertEq(cur.feeApr, 1e18);
        assertEq(cur.reservesInEth[0], 100e18);
        assertEq(cur.reservesInEth[1], 100e18);
        assertEq(cur.lastSnapshotTimestamp, prevTimestamp);
    }

    function test_Current_reservesChangedBetweenSnapshotAndCurrent() public {
        mockRethSWethBoostedPostion();
        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();

        uint256 prevTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        mockLSTData(address(rETHStats), 4e18);
        mockLSTData(address(swETHStats), 3e18);

        IDexLSTStats.DexLSTStatsData memory cur = calculator.current();

        assertEq(cur.feeApr, 1e18);
        assertEq(cur.reservesInEth[0], 100e18);
        assertEq(cur.reservesInEth[1], 100e18);
        assertEq(cur.lastSnapshotTimestamp, prevTimestamp);

        mockPositionReserves(0, 0);
        cur = calculator.current();
        // lower reseves between the last snapshot() and current() so we expect reservesInEth to be lower
        assertEq(cur.feeApr, 1e18);
        assertLe(cur.reservesInEth[0], 100e18);
        assertLe(cur.reservesInEth[1], 100e18);
        assertEq(cur.lastSnapshotTimestamp, prevTimestamp);
    }

    function testFuzz_scaleDecimalsToOriginal(uint256 decimals) public {
        vm.assume(decimals < 100);
        vm.assume(decimals > 1);
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenA.selector), abi.encode(RETH_MAINNET));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.tokenB.selector), abi.encode(SWETH_MAINNET));
        // because prices are in 1e18, decimals don't matter
        vm.mockCall(RETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));

        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: address(feeAprOracle)
        });

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = swETHStats.getAprId();

        mockPositionReserves(100e18, 100e18); // because getReserves scales everything to 1e18
        calculator.initialize(depAprIds, abi.encode(initData));

        mockFeeApr(1e18, uint40(block.timestamp));
        calculator.snapshot();

        mockLSTData(address(rETHStats), 4e18);
        mockLSTData(address(swETHStats), 3e18);

        IDexLSTStats.DexLSTStatsData memory cur = calculator.current();

        assertEq(cur.feeApr, 1e18);
        assertEq(cur.reservesInEth[0], 100e18);
        assertEq(cur.reservesInEth[1], 100e18);
    }
}
