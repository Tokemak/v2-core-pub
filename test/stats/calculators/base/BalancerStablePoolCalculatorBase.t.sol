// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Stats } from "src/stats/Stats.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import {
    TOKE_MAINNET,
    WETH_MAINNET,
    RETH_MAINNET,
    BAL_VAULT,
    RETH_WETH_BAL_POOL,
    WSTETH_MAINNET
} from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { IProtocolFeesCollector } from "src/interfaces/external/balancer/IProtocolFeesCollector.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { RethLSTCalculator } from "src/stats/calculators/RethLSTCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract BalancerStablePoolCalculatorBaseTest is Test {
    uint256 private constant TARGET_BLOCK = 17_580_732;
    uint256 private constant TARGET_BLOCK_TIMESTAMP = 1_687_990_535;
    uint256 private constant TARGET_BLOCK_VIRTUAL_PRICE = 1_023_521_727_648_403_073;
    uint256 private constant TARGET_BLOCK_RETH_BACKING = 1_075_219_009_833_433_231;
    uint256 private constant TARGET_BLOCK_RESERVE_0 = 22_043_317_920_246_255_530_254;
    uint256 private constant TARGET_BLOCK_RESERVE_1 = 23_967_981_419_922_593_304_842;

    // solhint-disable-next-line max-line-length
    bytes32 private constant RETH_WETH_POOL_ID = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112; //gitleaks:allow

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RethLSTCalculator private rETHStats;
    RootPriceOracle private rootPriceOracle;

    address private immutable mockWstethStats = vm.addr(1003);

    TestBalancerCalculator private calculator;

    event DexSnapshotTaken(uint256 snapshotTimestamp, uint256 priorFeeApr, uint256 newFeeApr, uint256 unfilteredFeeApr);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), TARGET_BLOCK);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));

        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        rETHStats = new RethLSTCalculator(systemRegistry);
        bytes32[] memory rETHDepAprIds = new bytes32[](0);
        LSTCalculatorBase.InitData memory rETHInitData = LSTCalculatorBase.InitData({ lstTokenAddress: RETH_MAINNET });
        mockTokenPrice(RETH_MAINNET, 1e18); // required for stats init
        rETHStats.initialize(rETHDepAprIds, abi.encode(rETHInitData));

        vm.prank(address(statsFactory));
        statsRegistry.register(address(rETHStats));

        calculator = new TestBalancerCalculator(systemRegistry, BAL_VAULT);
    }

    function testConstructorShouldRevertIfBalancerVaultZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_balancerVault"));
        new TestBalancerCalculator(systemRegistry, address(0));
    }

    function testConstructorShouldSetBalVault() public {
        assertEq(address(calculator.balancerVault()), BAL_VAULT);
    }

    function testInitializeRevertIfPoolAddressIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "poolAddress"));
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfPoolIdIsEmpty() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(RETH_WETH_BAL_POOL);

        mockPoolId(RETH_WETH_BAL_POOL, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(BalancerStablePoolCalculatorBase.InvalidPoolId.selector, RETH_WETH_BAL_POOL)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfNumTokensIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(RETH_WETH_BAL_POOL);

        address[] memory tokens = new address[](0);
        uint256[] memory balances = new uint256[](0);
        mockGetPoolTokens(RETH_WETH_POOL_ID, tokens, balances);

        vm.expectRevert(
            abi.encodeWithSelector(BalancerStablePoolCalculatorBase.InvalidPool.selector, RETH_WETH_BAL_POOL)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfNumTokenDependentAprIdsMismatch() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(RETH_WETH_BAL_POOL);

        address[] memory tokens = new address[](1);
        uint256[] memory balances = new uint256[](1);
        mockGetPoolTokens(RETH_WETH_POOL_ID, tokens, balances);

        vm.expectRevert(
            abi.encodeWithSelector(BalancerStablePoolCalculatorBase.DependentAprIdsMismatchTokens.selector, 2, 1)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfStatsAddressNotMatch() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = keccak256(abi.encode(RETH_MAINNET));
        bytes memory initData = getInitData(RETH_WETH_BAL_POOL);

        mockGetCalculator(depAprIds[0], mockWstethStats); // resolve to the wrong calculator
        mockStatsAddress(mockWstethStats, WSTETH_MAINNET);

        vm.expectRevert(
            abi.encodeWithSelector(Stats.CalculatorAssetMismatch.selector, depAprIds[0], mockWstethStats, RETH_MAINNET)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeSuccessfully() public {
        initializeSuccessfully();

        assertEq(calculator.numTokens(), 2);

        assertEq(address(calculator.lstStats(0)), address(rETHStats));
        assertEq(address(calculator.lstStats(1)), address(0));

        assertEq(calculator.reserveTokens(0), RETH_MAINNET);
        assertEq(calculator.reserveTokens(1), WETH_MAINNET);

        assertEq(calculator.poolId(), RETH_WETH_POOL_ID);
        assertEq(calculator.getAddressId(), RETH_WETH_BAL_POOL);
        assertEq(calculator.getAprId(), Stats.generateBalancerPoolIdentifier(RETH_WETH_BAL_POOL));

        assertEq(calculator.lastSnapshotTimestamp(), TARGET_BLOCK_TIMESTAMP);
        assertEq(calculator.feeApr(), 0);
        assertEq(calculator.lastVirtualPrice(), TARGET_BLOCK_VIRTUAL_PRICE);
        assertEq(calculator.lastEthPerShare(0), TARGET_BLOCK_RETH_BACKING);
        assertEq(calculator.lastEthPerShare(1), 0);
    }

    function testShouldNotSnapshotIfNotReady() public {
        initializeSuccessfully();
        assertFalse(calculator.shouldSnapshot());

        vm.expectRevert(abi.encodeWithSelector(IStatsCalculator.NoSnapshotTaken.selector));
        calculator.snapshot();
    }

    function testShouldSnapshot() public {
        initializeSuccessfully();
        assertFalse(calculator.shouldSnapshot());

        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        uint256 newVirtualPrice = TARGET_BLOCK_VIRTUAL_PRICE * 109 / 100; // increase by 9% over 9 days
        uint256 newEthPerShare = TARGET_BLOCK_RETH_BACKING * 109 / 100; // increase by 9% over 9 days

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(address(rETHStats), newEthPerShare);
        mockTokenPrice(RETH_MAINNET, 1e18);
        mockTokenPrice(WETH_MAINNET, 1e18);

        vm.expectEmit(true, true, true, false);
        emit DexSnapshotTaken(0, 0, 0, 0);

        calculator.snapshot();

        uint256 totalReserves = TARGET_BLOCK_RESERVE_0 + TARGET_BLOCK_RESERVE_1;
        uint256 baseApr = ((1e16 * 365) * TARGET_BLOCK_RESERVE_0) / totalReserves;
        uint256 baseAprLessAdmin = baseApr * 5e17 / 1e18; // 50% admin fee

        // 5% annualized for virtual price change
        uint256 rawFeeApr = 1e16 * 365;

        // calculate filtered feeApr with a starting 0
        uint256 expectedFeeApr = (rawFeeApr - baseAprLessAdmin);

        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastEthPerShare(0), newEthPerShare); // rETH
        assertEq(calculator.lastEthPerShare(1), 0); // weth
        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding errors
    }

    function testSnapshotShouldHandleZeroReserves() public {
        initializeSuccessfully();
        assertFalse(calculator.shouldSnapshot());

        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        uint256 newVirtualPrice = TARGET_BLOCK_VIRTUAL_PRICE * 109 / 100; // increase by 9% over 9 days
        uint256 newEthPerShare = TARGET_BLOCK_RETH_BACKING * 102 / 100; // increase by 2% over 9 days

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(address(rETHStats), newEthPerShare);
        mockTokenPrice(RETH_MAINNET, 1e18);
        mockTokenPrice(WETH_MAINNET, 1e18);

        address[] memory tokens = new address[](2);
        uint256[] memory balances = new uint256[](2); // set balances to zero
        mockGetPoolTokens(RETH_WETH_POOL_ID, tokens, balances);
        calculator.snapshot();

        // NOTE: it isn't possible for virtual price to increase without any reserves
        // but testing the edge case
        uint256 expectedFeeApr = 9e16 / 9 * 365; // 9% annualized

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50);
    }

    function testSnapshotShouldClipNegativeFee() public {
        initializeSuccessfully();
        assertFalse(calculator.shouldSnapshot());

        // move past allowed snapshot time
        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        // increase virtual price and snapshot so that feeApr isn't 0
        uint256 newVirtualPrice = TARGET_BLOCK_VIRTUAL_PRICE * 109 / 100; // increase by 9%
        mockVirtualPrice(newVirtualPrice);
        mockTokenPrice(RETH_MAINNET, 1e18);
        mockTokenPrice(WETH_MAINNET, 1e18);
        calculator.snapshot();

        uint256 priorFeeApr = calculator.feeApr();
        assertGt(priorFeeApr, 0);

        newTimestamp += Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);

        // increase virtualPrice by 1%
        newVirtualPrice = newVirtualPrice * 101 / 100;

        // increase rETH backing by 5% to fully offset the virtual price change
        // 5% * ~50% reserve balance * 50% admin fee = 1.25%
        uint256 newEthPerShare = TARGET_BLOCK_RETH_BACKING * 105 / 100; // increase by 5%

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(address(rETHStats), newEthPerShare);
        mockTokenPrice(RETH_MAINNET, 1e18);
        mockTokenPrice(WETH_MAINNET, 1e18);
        calculator.snapshot();

        // add a 0% to the filter
        uint256 expectedFeeApr = priorFeeApr * 9e17 / 1e18;

        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastEthPerShare(0), newEthPerShare); // rETH
        assertEq(calculator.lastEthPerShare(1), 0); // weth
        assertEq(calculator.feeApr(), expectedFeeApr);
    }

    function testCurrent() public {
        initializeSuccessfully();
        mockTokenPrice(RETH_MAINNET, 55e16); // set to arbitrary price
        mockTokenPrice(WETH_MAINNET, 1e18); // set to 1:1

        uint256[] memory emptyArr = new uint256[](0);
        mockLSTData(address(rETHStats), 12, emptyArr, emptyArr);

        IDexLSTStats.DexLSTStatsData memory current = calculator.current();

        uint256 expectedReserve0 = TARGET_BLOCK_RESERVE_0 * 55e16 / 1e18;

        assertEq(current.feeApr, 0);
        assertEq(current.reservesInEth.length, 2);
        assertEq(current.reservesInEth[0], expectedReserve0);
        assertEq(current.reservesInEth[1], TARGET_BLOCK_RESERVE_1);

        assertEq(current.lstStatsData.length, 2);
        assertEq(current.lstStatsData[0].baseApr, 6); // reduced by bal admin fee
        assertEq(current.lstStatsData[0].slashingCosts.length, 0);
        assertEq(current.lstStatsData[0].slashingTimestamps.length, 0);

        assertEq(current.lstStatsData[1].baseApr, 0);
        assertEq(current.lstStatsData[1].slashingCosts.length, 0);
        assertEq(current.lstStatsData[1].slashingTimestamps.length, 0);

        assertEq(current.lastSnapshotTimestamp, TARGET_BLOCK_TIMESTAMP);
    }

    function testItShouldHandleReserveTokensDecimals() public {
        mockTokenDecimals(RETH_MAINNET, 12); // set rETH to be 12 decimals instead of 18
        initializeSuccessfully();

        mockTokenPrice(RETH_MAINNET, 1e18); // set to 1:1
        mockTokenPrice(WETH_MAINNET, 1e18); // set to 1:1

        IDexLSTStats.DexLSTStatsData memory current = calculator.current();
        assertEq(current.reservesInEth[0], TARGET_BLOCK_RESERVE_0 * 1e6); // pad by 18 vs 12 decimals
        assertEq(current.reservesInEth[1], TARGET_BLOCK_RESERVE_1);
    }

    function initializeSuccessfully() internal {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = rETHStats.getAprId();
        depAprIds[1] = Stats.NOOP_APR_ID;
        bytes memory initData = getInitData(RETH_WETH_BAL_POOL);

        calculator.initialize(depAprIds, initData);
    }

    function getInitData(address poolAddress) internal pure returns (bytes memory) {
        return abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: poolAddress }));
    }

    function mockPoolId(address pool, bytes32 res) internal {
        vm.mockCall(pool, abi.encodeWithSelector(IBalancerPool.getPoolId.selector), abi.encode(res));
    }

    function mockGetPoolTokens(bytes32 poolId, address[] memory tokens, uint256[] memory balances) internal {
        vm.mockCall(
            BAL_VAULT, abi.encodeWithSelector(IVault.getPoolTokens.selector, poolId), abi.encode(tokens, balances)
        );
    }

    function mockGetCalculator(bytes32 aprId, address stats) internal {
        vm.mockCall(
            address(statsRegistry),
            abi.encodeWithSelector(IStatsCalculatorRegistry.getCalculator.selector, aprId),
            abi.encode(IStatsCalculator(stats))
        );
    }

    function mockStatsAddress(address stats, address res) internal {
        vm.mockCall(stats, abi.encodeWithSelector(IStatsCalculator.getAddressId.selector), abi.encode(res));
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function mockLSTData(
        address stats,
        uint256 baseApr,
        uint256[] memory slashingCosts,
        uint256[] memory slashingTimestamps
    ) internal {
        uint24[10] memory discountHistory;
        uint40[5] memory discountTimestampByPercent;
        ILSTStats.LSTStatsData memory res = ILSTStats.LSTStatsData({
            lastSnapshotTimestamp: 0,
            baseApr: baseApr,
            discount: 0,
            discountHistory: discountHistory,
            discountTimestampByPercent: discountTimestampByPercent,
            slashingCosts: slashingCosts,
            slashingTimestamps: slashingTimestamps
        });
        vm.mockCall(stats, abi.encodeWithSelector(ILSTStats.current.selector), abi.encode(res));
    }

    function mockTokenDecimals(address token, uint8 decimals) internal {
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
    }

    function mockVirtualPrice(uint256 virtualPrice) internal {
        vm.mockCall(
            RETH_WETH_BAL_POOL,
            abi.encodeWithSelector(IBalancerMetaStablePool.getRate.selector),
            abi.encode(virtualPrice)
        );
    }

    function mockStatsEthPerToken(address stats, uint256 value) internal {
        vm.mockCall(stats, abi.encodeWithSelector(ILSTStats.calculateEthPerToken.selector), abi.encode(value));
    }
}

contract TestBalancerCalculator is BalancerStablePoolCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry,
        address vault
    ) BalancerStablePoolCalculatorBase(_systemRegistry, vault) { }

    function getVirtualPrice() internal view override returns (uint256) {
        // Note: this does not correct for an issue related to balancer not accruing admin fees
        return IBalancerMetaStablePool(poolAddress).getRate();
    }

    function getPoolTokens() internal view override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances,) = IVault(balancerVault).getPoolTokens(poolId);
    }
}
