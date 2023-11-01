// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Stats } from "src/stats/Stats.sol";
import { CurvePoolRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolRebasingCalculatorBase.sol";
import { ICurveRegistry } from "src/interfaces/external/curve/ICurveRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { StethLSTCalculator } from "src/stats/calculators/StethLSTCalculator.sol";
import {
    TOKE_MAINNET,
    WETH_MAINNET,
    STETH_ETH_CURVE_POOL,
    STETH_MAINNET,
    CURVE_META_REGISTRY_MAINNET
} from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { ICurveV1StableSwap } from "src/interfaces/external/curve/ICurveV1StableSwap.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { CurveV1PoolRebasingStatsCalculator } from "src/stats/calculators/CurveV1PoolRebasingStatsCalculator.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IPool } from "src/interfaces/external/curve/IPool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CurveV1PoolRebasingStatsCalculatorTest is Test {
    uint256 private constant TARGET_BLOCK = 17_580_732;
    uint256 private constant TARGET_BLOCK_TIMESTAMP = 1_687_990_535;
    uint256 private constant TARGET_BLOCK_VIRTUAL_PRICE = 1_075_397_350_175_479_003;
    address private constant TARGET_POOL = STETH_ETH_CURVE_POOL;

    uint256 private constant TARGET_BLOCK_RESERVE_0 = 230_718_834_780_795_563_400_027;
    uint256 private constant TARGET_BLOCK_RESERVE_1 = 231_463_950_768_086_217_156_038;

    address private immutable mockStatsRegistryAddr = vm.addr(1001);
    address private immutable mockStethStats = vm.addr(1002);
    address private immutable mockPricer = vm.addr(1004);

    ICurveResolver private curveResolver;
    SystemRegistry private systemRegistry;
    AccessController private accessController;

    CurveV1PoolRebasingStatsCalculator private calculator;

    event DexSnapshotTaken(uint256 snapshotTimestamp, uint256 priorFeeApr, uint256 newFeeApr, uint256 unfilteredFeeApr);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), TARGET_BLOCK);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));
        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));

        calculator = new CurveV1PoolRebasingStatsCalculator(systemRegistry);

        vm.clearMockedCalls();
        mockGetCurveResolver(); // bypass systemRegistry
        mockStatsRegistry(); // bypass systemRegistry
        mockGetRootPriceOracle(); // bypass systemRegistry
    }

    function testInitializeRevertIfPoolAddressIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "poolAddress"));
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfLpTokenIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(TARGET_POOL, 1);

        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(address(0), address(0)), 0, address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfNCoinsIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(TARGET_POOL, 1);

        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(address(0), address(0)), 0, TARGET_POOL);

        vm.expectRevert(abi.encodeWithSelector(CurvePoolRebasingCalculatorBase.InvalidPool.selector, TARGET_POOL));
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfNumTokenDependentAprIdsMismatch() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(TARGET_POOL, 1);

        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(address(0), address(0)), 1, TARGET_POOL);

        vm.expectRevert(
            abi.encodeWithSelector(CurvePoolRebasingCalculatorBase.DependentAprIdsMismatchTokens.selector, 2, 1)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfRebasingTokensOutOfIndex() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(TARGET_POOL, 3);

        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(Stats.CURVE_ETH, STETH_MAINNET), 2, TARGET_POOL);

        vm.expectRevert(
            abi.encodeWithSelector(CurvePoolRebasingCalculatorBase.InvalidRebasingTokenIndex.selector, 3, 2)
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfStatsAddressNotMatch() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = keccak256(abi.encode(STETH_MAINNET));
        bytes memory initData = getInitData(TARGET_POOL, 1);

        address wrongToken = vm.addr(8888);
        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(Stats.CURVE_ETH, STETH_MAINNET), 2, TARGET_POOL);
        mockGetCalculator(depAprIds[0], mockStethStats);
        mockStatsAddress(mockStethStats, wrongToken); // resolve to the wrong token address

        vm.expectRevert(
            abi.encodeWithSelector(
                Stats.CalculatorAssetMismatch.selector, depAprIds[0], mockStethStats, Stats.CURVE_ETH
            )
        );
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeSuccessfully() public {
        initializeSuccessfully(1);

        assertEq(calculator.poolAddress(), TARGET_POOL);
        assertEq(calculator.lpToken(), TARGET_POOL);
        assertEq(calculator.lastSnapshotTimestamp(), TARGET_BLOCK_TIMESTAMP);
        assertEq(calculator.lastVirtualPrice(), TARGET_BLOCK_VIRTUAL_PRICE);

        assertEq(calculator.numTokens(), 2);

        assertEq(address(calculator.lstStats(0)), address(0));
        assertEq(address(calculator.lstStats(1)), mockStethStats);

        assertEq(calculator.reserveTokens(0), Stats.CURVE_ETH);
        assertEq(calculator.reserveTokens(1), STETH_MAINNET);
    }

    function testShouldNotSnapshotIfNotReady() public {
        initializeSuccessfully(1);
        assertFalse(calculator.shouldSnapshot());

        vm.expectRevert(abi.encodeWithSelector(IStatsCalculator.NoSnapshotTaken.selector));
        calculator.snapshot();
    }

    function testSnapshotShouldUpdateFeeApr() public {
        uint256 startingEthPerShare = 1e18;
        initializeSuccessfully(startingEthPerShare);

        // move past allowed snapshot time
        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        uint256 newVirtualPrice = (TARGET_BLOCK_VIRTUAL_PRICE * 109) / 100; // increase by 9% over 9 days
        uint256 newEthPerShare = startingEthPerShare * 109 / 100; // increase by 4% over 9 days

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);
        calculator.snapshot();

        uint256 annualizedFeeChg = 9 * 1e16 / 9 * 365; // 9% change over 9 days then annualized w/ *365

        uint256 annualizedBaseApr = (9 / 9 * 1e16 * 365); // 9% over 9 days
        uint256 scaledBaseApr =
            annualizedBaseApr * TARGET_BLOCK_RESERVE_1 / (TARGET_BLOCK_RESERVE_0 + TARGET_BLOCK_RESERVE_1);

        // expectedFeeApr = feeChg - scaledBaseYield
        uint256 expectedFeeApr = (annualizedFeeChg - scaledBaseApr);

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding loss
        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastRebasingTokenEthPerShare(), newEthPerShare);

        // next sample: move past allowed snapshot time
        newTimestamp = newTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());

        newVirtualPrice = newVirtualPrice * 105 / 100; // increase by 5%
        newEthPerShare = newEthPerShare * 101 / 100; // increase by 1%

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);

        annualizedBaseApr = (1 * 1e16 * 365); // 1% annualized
        scaledBaseApr = annualizedBaseApr * TARGET_BLOCK_RESERVE_1 / (TARGET_BLOCK_RESERVE_0 + TARGET_BLOCK_RESERVE_1);

        annualizedFeeChg = (5 * 1e16 * 365); // 5% annualized

        // expectedFeeApr = feeChg - scaledBaseYield
        expectedFeeApr = (
            (calculator.feeApr() * (1e18 - Stats.DEX_FEE_ALPHA))
                + ((annualizedFeeChg - scaledBaseApr) * Stats.DEX_FEE_ALPHA)
        ) / 1e18;

        vm.expectEmit(true, true, true, false);
        emit DexSnapshotTaken(0, 0, 0, 0);

        calculator.snapshot();

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding loss
        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastRebasingTokenEthPerShare(), newEthPerShare);
    }

    function testSnapshotShouldClipNegativeFee() public {
        uint256 startingEthPerShare = 1e18;
        initializeSuccessfully(startingEthPerShare);

        // move past allowed snapshot time
        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        uint256 newVirtualPrice = (TARGET_BLOCK_VIRTUAL_PRICE * 109) / 100; // increase by 9% over 9 days
        uint256 newEthPerShare = startingEthPerShare * 109 / 100; // increase by 4% over 9 days

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);
        calculator.snapshot();

        uint256 annualizedFeeChg = 9 * 1e16 / 9 * 365; // 9% change over 9 days then annualized w/ *365

        uint256 annualizedBaseApr = (9 / 9 * 1e16 * 365); // 9% over 9 days
        uint256 scaledBaseApr =
            annualizedBaseApr * TARGET_BLOCK_RESERVE_1 / (TARGET_BLOCK_RESERVE_0 + TARGET_BLOCK_RESERVE_1);

        // expectedFeeApr = feeChg - scaledBaseYield
        uint256 expectedFeeApr = (annualizedFeeChg - scaledBaseApr);

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding loss
        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastRebasingTokenEthPerShare(), newEthPerShare);

        // next sample: move past allowed snapshot time
        newTimestamp = newTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);

        // after this snapshot the feeApr = 5% * 365 * 0.1
        // we hold the ethPerShare constant so that the feeReturn == change in virtualPrice
        newVirtualPrice = (newVirtualPrice * 105) / 100; // increase by 5%
        newEthPerShare = startingEthPerShare; // hold ethPerShare constant
        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);
        calculator.snapshot();

        // after this snapshot the feeApr = XX
        // we increase the virtualPrice, but increase the base yield by more
        // resulting in a zero fee apr
        newTimestamp = newTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);
        newVirtualPrice = (newVirtualPrice * 101) / 100; // increase by 1%
        newEthPerShare = newEthPerShare * 104 / 100; // increase by 4%
        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);

        expectedFeeApr = ((calculator.feeApr() * (1e18 - Stats.DEX_FEE_ALPHA)) + (0 * Stats.DEX_FEE_ALPHA)) / 1e18;
        calculator.snapshot();

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding loss
        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastRebasingTokenEthPerShare(), newEthPerShare);
    }

    function testSnapshotShouldHandleZeroReserves() public {
        uint256 startingEthPerShare = 1e18;
        initializeSuccessfully(startingEthPerShare);

        // move past allowed snapshot time
        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        vm.warp(newTimestamp);
        assertTrue(calculator.shouldSnapshot());
        assertEq(calculator.feeApr(), 0);

        uint256 newVirtualPrice = (TARGET_BLOCK_VIRTUAL_PRICE * 109) / 100; // increase by 9% over 9 days
        uint256 newEthPerShare = startingEthPerShare * 109 / 100; // increase by 4% over 9 days

        mockVirtualPrice(newVirtualPrice);
        mockStatsEthPerToken(mockStethStats, newEthPerShare);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);
        calculator.snapshot();

        uint256 annualizedFeeChg = 9 * 1e16 / 9 * 365; // 9% change over 9 days then annualized w/ *365

        uint256 annualizedBaseApr = (9 / 9 * 1e16 * 365); // 9% over 9 days
        uint256 scaledBaseApr =
            annualizedBaseApr * TARGET_BLOCK_RESERVE_1 / (TARGET_BLOCK_RESERVE_0 + TARGET_BLOCK_RESERVE_1);

        // expectedFeeApr = feeChg - scaledBaseYield
        uint256 expectedFeeApr = (annualizedFeeChg - scaledBaseApr);

        assertApproxEqAbs(calculator.feeApr(), expectedFeeApr, 50); // allow for rounding loss
        assertEq(calculator.lastSnapshotTimestamp(), newTimestamp);
        assertEq(calculator.lastVirtualPrice(), newVirtualPrice);
        assertEq(calculator.lastRebasingTokenEthPerShare(), newEthPerShare);

        // next sample: move past allowed snapshot time
        uint256 lastfeeApr = calculator.feeApr(); // record last fee APR
        newTimestamp = newTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);

        mockVirtualPrice(TARGET_BLOCK_VIRTUAL_PRICE + 1e12);
        mockStatsEthPerToken(mockStethStats, 1);
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);
        mockPoolReserves(0, 0);

        calculator.snapshot();

        // just check that it has moved
        assertFalse(calculator.feeApr() == lastfeeApr);
    }

    function testItShouldHandleReserveTokensDecimals() public {
        mockTokenDecimals(STETH_MAINNET, 12); // set stETH to be 12 decimals instead of 18
        initializeSuccessfully(1);

        // move past allowed snapshot time
        uint256 newTimestamp = TARGET_BLOCK_TIMESTAMP + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        vm.warp(newTimestamp);

        mockVirtualPrice(TARGET_BLOCK_VIRTUAL_PRICE + 1e12);
        mockStatsEthPerToken(mockStethStats, 1);

        uint256[] memory noSlashing = new uint256[](0);
        mockLSTData(mockStethStats, 10, noSlashing, noSlashing);

        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, 1e18);

        // set stETH reserve to 1e12 so that if decimals are handled correctly
        // the result should be it it ends up at 1e18
        mockPoolReserves(1e18, 1e12);

        IDexLSTStats.DexLSTStatsData memory current = calculator.current();
        assertEq(current.reservesInEth[0], 1e18);
        assertEq(current.reservesInEth[1], 1e18);
    }

    function testCurrent() public {
        initializeSuccessfully(1);

        uint256[] memory noSlashing = new uint256[](0);
        mockLSTData(mockStethStats, 10, noSlashing, noSlashing);

        uint256 stethPrice = 5e17; // cut price of steth by 50% to test reserve calcs
        mockTokenPrice(Stats.CURVE_ETH, 1e18);
        mockTokenPrice(STETH_MAINNET, stethPrice);

        IDexLSTStats.DexLSTStatsData memory current = calculator.current();

        assertEq(current.feeApr, 0);
        assertEq(current.reservesInEth.length, 2);
        assertEq(current.reservesInEth[0], TARGET_BLOCK_RESERVE_0);
        assertEq(current.reservesInEth[1], TARGET_BLOCK_RESERVE_1 * stethPrice / 1e18);

        assertEq(current.lstStatsData.length, 2);
        assertEq(current.lstStatsData[0].baseApr, 0);
        assertEq(current.lstStatsData[0].slashingCosts.length, 0);
        assertEq(current.lstStatsData[0].slashingTimestamps.length, 0);

        assertEq(current.lstStatsData[1].baseApr, 10);
        assertEq(current.lstStatsData[1].slashingCosts.length, 0);
        assertEq(current.lstStatsData[1].slashingTimestamps.length, 0);

        assertEq(current.lastSnapshotTimestamp, TARGET_BLOCK_TIMESTAMP);
    }

    function initializeSuccessfully(uint256 startingEthPerToken) internal {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = keccak256(abi.encode(STETH_MAINNET));
        bytes memory initData = getInitData(TARGET_POOL, 1);

        mockResolveWithLpToken(TARGET_POOL, buildCoinsArray(Stats.CURVE_ETH, STETH_MAINNET), 2, TARGET_POOL);
        mockGetCalculator(depAprIds[1], mockStethStats);
        mockStatsAddress(mockStethStats, STETH_MAINNET);
        mockStatsEthPerToken(mockStethStats, startingEthPerToken);

        calculator.initialize(depAprIds, initData);
    }

    function mockGetCurveResolver() internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(SystemRegistry.curveResolver.selector),
            abi.encode(curveResolver)
        );
    }

    function mockResolveWithLpToken(
        address poolAddress,
        address[8] memory reserveTokens,
        uint256 numTokens,
        address lpToken
    ) internal {
        vm.mockCall(
            address(curveResolver),
            abi.encodeWithSelector(ICurveResolver.resolveWithLpToken.selector, poolAddress),
            abi.encode(reserveTokens, numTokens, lpToken, true)
        );
    }

    function mockStatsRegistry() internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(SystemRegistry.statsCalculatorRegistry.selector),
            abi.encode(mockStatsRegistryAddr)
        );
    }

    function mockGetRootPriceOracle() internal {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(SystemRegistry.rootPriceOracle.selector),
            abi.encode(mockPricer)
        );
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            mockPricer, abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token), abi.encode(price)
        );
    }

    function mockGetCalculator(bytes32 aprId, address stats) internal {
        vm.mockCall(
            mockStatsRegistryAddr,
            abi.encodeWithSelector(IStatsCalculatorRegistry.getCalculator.selector, aprId),
            abi.encode(IStatsCalculator(stats))
        );
    }

    function mockStatsAddress(address stats, address res) internal {
        vm.mockCall(stats, abi.encodeWithSelector(IStatsCalculator.getAddressId.selector), abi.encode(res));
    }

    function mockStatsEthPerToken(address stats, uint256 value) internal {
        vm.mockCall(stats, abi.encodeWithSelector(ILSTStats.calculateEthPerToken.selector), abi.encode(value));
    }

    function mockPoolReserves(uint256 token0Amount, uint256 token1Amount) internal {
        vm.mockCall(TARGET_POOL, abi.encodeWithSelector(IPool.balances.selector, 0), abi.encode(token0Amount));
        vm.mockCall(TARGET_POOL, abi.encodeWithSelector(IPool.balances.selector, 1), abi.encode(token1Amount));
    }

    function mockTokenDecimals(address token, uint8 decimals) internal {
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
    }

    function mockVirtualPrice(uint256 virtualPrice) internal {
        vm.mockCall(
            STETH_ETH_CURVE_POOL,
            abi.encodeWithSelector(ICurveV1StableSwap.get_virtual_price.selector),
            abi.encode(virtualPrice)
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

    function getInitData(address poolAddress, uint256 rebasingTokenIdx) internal pure returns (bytes memory) {
        return abi.encode(
            CurvePoolRebasingCalculatorBase.InitData({ poolAddress: poolAddress, rebasingTokenIdx: rebasingTokenIdx })
        );
    }

    function buildCoinsArray(address token0, address token1) internal pure returns (address[8] memory) {
        return [token0, token1, address(0), address(0), address(0), address(0), address(0), address(0)];
    }
}
