// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

// solhint-disable max-states-count

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { AerodromeStakingDexCalculator } from "src/stats/calculators/AerodromeStakingDexCalculator.sol";
import { AerodromeStakingIncentiveCalculator } from "src/stats/calculators/AerodromeStakingIncentiveCalculator.sol";
import { IAerodromeGauge } from "src/interfaces/external/aerodrome/IAerodromeGauge.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IERC20 } from "lib/forge-std/src/interfaces/IERC20.sol";
import { WETH9_BASE, RETH_BASE } from "test/utils/Addresses.sol";
import { IPool } from "src/interfaces/external/aerodrome/IPool.sol";
import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { Errors } from "src/utils/Errors.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";

// solhint-disable func-name-mixedcase
contract AerodromeStakingIncentiveCalculatorTest is Test {
    uint256 private constant TARGET_BLOCK = 13_719_843;
    uint256 private constant TARGET_TIMESTAMP = 1_714_229_033;

    AerodromeStakingDexCalculator private underlyerStats;
    AerodromeStakingIncentiveCalculator private calculator;

    address public constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address private mockToke = vm.addr(22);
    address private pool = vm.addr(33);
    address private gauge = vm.addr(44);
    address private incentivePricingStats = vm.addr(55);

    // 18e24 is the safeTotalSupply calc when two snapshots of (rewardPerToken = 1000 + 10) in 5 hours
    // @notice mockTotalSupply from MaverickCalculator.t.sol
    uint256 private mockTotalSupply = 18e24;
    // uint256 private mockSafeTotalSupply = 1080000000000000000000;

    uint256 private mockRewardRate = 10_000;
    uint256 private mockRewardPerToken = 1000;
    uint256 private mockPeriodFinish = TARGET_TIMESTAMP + 7 days; // a week after block.timestamp
    // need reasonable values for

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RootPriceOracle private rootPriceOracle;

    IIncentivesPricingStats private incentivePricing;

    error InvalidScenario();

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

        incentivePricing = IIncentivesPricingStats(incentivePricingStats);

        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(systemRegistry.incentivePricing.selector),
            abi.encode(incentivePricingStats)
        );

        vm.mockCall(pool, abi.encodeWithSelector(IPool.token0.selector), abi.encode(WETH9_BASE));
        vm.mockCall(pool, abi.encodeWithSelector(IPool.token1.selector), abi.encode(RETH_BASE));
        // mock pool is (WETH, rETH)
        underlyerStats =
            AerodromeStakingDexCalculator(Clones.clone(address(new AerodromeStakingDexCalculator(systemRegistry))));
        calculator = AerodromeStakingIncentiveCalculator(
            Clones.clone(address(new AerodromeStakingIncentiveCalculator(systemRegistry)))
        );

        IDexLSTStats.DexLSTStatsData memory data = IDexLSTStats.DexLSTStatsData({
            lastSnapshotTimestamp: 0,
            feeApr: 0,
            reservesInEth: new uint256[](0),
            stakingIncentiveStats: IDexLSTStats.StakingIncentiveStats({
                safeTotalSupply: 0,
                rewardTokens: new address[](0),
                annualizedRewardAmounts: new uint256[](0),
                periodFinishForRewards: new uint40[](0),
                incentiveCredits: 0
            }),
            lstStatsData: new ILSTStats.LSTStatsData[](0)
        });

        vm.mockCall(address(underlyerStats), abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(data));
    }

    function setIncentivePrice(address token, uint256 fastPrice, uint256 slowPrice) private {
        vm.mockCall(
            incentivePricingStats,
            abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector, token, calculator.PRICE_STALE_CHECK()),
            abi.encode(fastPrice, slowPrice)
        );
    }

    function mockTokenPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function successfulInitalizeDexCalculator() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;
        bytes memory initData = abi.encode(AerodromeStakingDexCalculator.InitData({ poolAddress: address(pool) }));
        underlyerStats.initialize(depAprIds, initData);
    }

    function successfulInitalizeIncentiveCalculator() public {
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardToken.selector), abi.encode(AERO));
        vm.mockCall(AERO, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(18));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.stakingToken.selector), abi.encode(pool));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.isPool.selector), abi.encode(true));

        bytes32[] memory depAprIds = new bytes32[](0);
        bytes memory initData = abi.encode(
            AerodromeStakingIncentiveCalculator.InitData({
                poolAddress: address(pool),
                gaugeAddress: address(gauge),
                underlyerStats: address(underlyerStats)
            })
        );
        calculator.initialize(depAprIds, initData);
    }

    function mockDefaultData() internal {
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector), abi.encode(mockTotalSupply));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode(mockRewardRate));
        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector), abi.encode(mockRewardPerToken)
        );
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector), abi.encode(mockPeriodFinish));
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector),
            abi.encode(0, 1e18, true)
        );

        setIncentivePrice(AERO, 1e32, 1e32); // mock token price very high to so that it passes NON_TRIVIAL_ANNUAL_RATE
    }

    function successfulInitalize() public {
        successfulInitalizeDexCalculator();
        successfulInitalizeIncentiveCalculator();
    }

    function _runScenario(
        uint256[] memory rewardRates,
        uint256[] memory totalSupply,
        uint256[] memory rewardPerToken,
        uint256[] memory time
    ) internal {
        if (
            rewardRates.length != totalSupply.length || rewardRates.length != rewardPerToken.length
                || rewardRates.length != time.length
        ) {
            revert InvalidScenario();
        }

        // period finish far in the future
        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector), abi.encode(block.timestamp + 100 days)
        );

        for (uint256 i = 0; i < rewardRates.length; i++) {
            vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode(rewardRates[i]));
            //solhint-disable-next-line max-line-length
            vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector), abi.encode(totalSupply[i]));
            vm.mockCall(
                gauge, abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector), abi.encode(rewardPerToken[i])
            );

            calculator.snapshot();
            vm.warp(block.timestamp + time[i]);
        }
    }

    function test_RevertIf_InitalizePoolGaugeMismatch() public {
        successfulInitalizeDexCalculator();
        vm.mockCall(AERO, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(18));

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardToken.selector), abi.encode(AERO));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.stakingToken.selector), abi.encode(address(1)));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.isPool.selector), abi.encode(true));

        bytes32[] memory depAprIds = new bytes32[](0);
        bytes memory initData = abi.encode(
            AerodromeStakingIncentiveCalculator.InitData({
                poolAddress: address(pool),
                gaugeAddress: address(gauge),
                underlyerStats: address(underlyerStats)
            })
        );
        vm.expectRevert(AerodromeStakingIncentiveCalculator.GaugePoolMismatch.selector);
        calculator.initialize(depAprIds, initData);
    }

    function test_RevertIf_InitalizeGaugeIsPoolIsFalse() public {
        successfulInitalizeDexCalculator();
        vm.mockCall(AERO, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(18));

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardToken.selector), abi.encode(AERO));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.stakingToken.selector), abi.encode(pool));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.isPool.selector), abi.encode(false));

        bytes32[] memory depAprIds = new bytes32[](0);
        bytes memory initData = abi.encode(
            AerodromeStakingIncentiveCalculator.InitData({
                poolAddress: address(pool),
                gaugeAddress: address(gauge),
                underlyerStats: address(underlyerStats)
            })
        );
        vm.expectRevert(AerodromeStakingIncentiveCalculator.GaugeNotForLegitimatePool.selector);
        calculator.initialize(depAprIds, initData);
    }

    function test_RevertIf_InitalizeRewardTokenDoesNotHave18Decimals() public {
        successfulInitalizeDexCalculator();
        vm.mockCall(AERO, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(6));

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardToken.selector), abi.encode(AERO));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.stakingToken.selector), abi.encode(pool));
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.isPool.selector), abi.encode(true));

        bytes32[] memory depAprIds = new bytes32[](0);
        bytes memory initData = abi.encode(
            AerodromeStakingIncentiveCalculator.InitData({
                poolAddress: address(pool),
                gaugeAddress: address(gauge),
                underlyerStats: address(underlyerStats)
            })
        );
        vm.expectRevert(AerodromeStakingIncentiveCalculator.RewardTokenNot18Decimals.selector);
        calculator.initialize(depAprIds, initData);
    }

    function testSuccessfulInitalize() public {
        successfulInitalize();
        assertEq(address(calculator.pool()), pool);
        assertEq(address(calculator.gauge()), gauge);
        assertEq(address(calculator.underlyerStats()), address(underlyerStats));
        assertEq(calculator.reserveTokens(0), WETH9_BASE);
        assertEq(calculator.reserveTokens(1), RETH_BASE);
        assertEq(calculator.lastIncentiveTimestamp(), block.timestamp);
        assertEq(calculator.decayInitTimestamp(), block.timestamp);
        assertEq(calculator.decayState(), false);
    }

    function testSnapshotHappyPath() public {
        successfulInitalize();
        mockDefaultData();

        calculator.snapshot();
        assertEq(calculator.lastSnapshotRewardPerToken(), mockRewardPerToken + 1);
        assertEq(calculator.lastSnapshotRewardRate(), mockRewardRate);
        assertEq(calculator.lastSnapshotTimestamp(), block.timestamp);
        assertEq(calculator.lastIncentiveTimestamp(), block.timestamp);
        assertEq(calculator.shouldSnapshot(), false);
        vm.warp(block.timestamp + 5 hours);

        // increase reward per token to show that AERO was emitted
        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector), abi.encode(mockRewardPerToken + 10)
        );
        // finalizing snapshot
        calculator.snapshot();

        assertEq(calculator.shouldSnapshot(), false);
        assertEq(calculator.lastSnapshotTimestamp(), block.timestamp);
        assertEq(calculator.lastSnapshotRewardPerToken(), 0);
        assertEq(calculator.safeTotalSupply(), mockTotalSupply);
        assertEq(calculator.lastSnapshotRewardRate(), mockRewardRate);
        assertEq(calculator.decayState(), false);
        assertEq(calculator.incentiveCredits(), 0);
        assertGt(calculator.lastSnapshotTotalAPR(), 0);

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();

        assertGt(res.stakingIncentiveStats.safeTotalSupply, 0);
        assertEq(res.stakingIncentiveStats.periodFinishForRewards[0], mockPeriodFinish);
        assertEq(res.stakingIncentiveStats.annualizedRewardAmounts[0], mockRewardRate * Stats.SECONDS_IN_YEAR);
        assertEq(res.stakingIncentiveStats.rewardTokens[0], AERO);
        assertEq(res.stakingIncentiveStats.incentiveCredits, 0);
    }

    function create2StepsSnapshot() internal {
        successfulInitalize();
        mockDefaultData();
        calculator.snapshot();
        vm.warp(block.timestamp + 5 hours);

        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector), abi.encode(mockRewardPerToken + 10)
        );
        calculator.snapshot();
    }

    function testShouldSnapshotEarlyRestartIfRewardRateChangebyMoreThanFivePercent() public {
        // second to end
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());

        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode((mockRewardRate * 106) / 100)
        );
        assertTrue(calculator.shouldSnapshot());

        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode((mockRewardRate * 94) / 100)
        );
        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotRestartSnapshotProcessIfRewardRateChangesMidway() public {
        successfulInitalize();
        mockDefaultData();
        calculator.snapshot();
        assertFalse(calculator.shouldSnapshot());

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode(mockRewardRate + 1));
        assertTrue(calculator.shouldSnapshot());

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode(mockRewardRate - 1));
        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotRestartSnapshotIfCurrentTimeIsAfterPeriodFinish() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 1 days + 1);
        assertTrue(calculator.shouldSnapshot());

        vm.mockCall(
            gauge, abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector), abi.encode(block.timestamp - 1)
        );

        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotRestartSnapshotAfterADayEvenIfRewardRateIsZero() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 1 days + 1);
        assertTrue(calculator.shouldSnapshot());

        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.rewardRate.selector), abi.encode(0));

        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotDontRestartBefore24Hours() public {
        create2StepsSnapshot();

        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 24 hours);
        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 1);
        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotRestartEarlyfTotalSupplyIsZero() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector), abi.encode(0));
        assertTrue(calculator.shouldSnapshot());
    }

    function testShouldSnapshotEarlyRestartSnapshotIfTotalSupplyDeviatesByAtLeast5PercentAfter6Hours() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector),
            abi.encode((mockTotalSupply * 106) / 100)
        );
        assertFalse(calculator.shouldSnapshot());

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector),
            abi.encode((mockTotalSupply * 94) / 100)
        );
        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 6 hours + 1);
        assertTrue(calculator.shouldSnapshot());
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.totalSupply.selector), abi.encode(mockTotalSupply));
        assertFalse(calculator.shouldSnapshot());
    }

    function testFuzzOnlyUpdateSafeTotalSupplyWhenRewardPerTokenIncreasedAndPeriodFinishIsInTheFuture(
        bool periodFinishInFuture,
        bool rewardPerTokenIncreased
    ) public {
        successfulInitalize();
        mockDefaultData();
        calculator.snapshot();
        vm.warp(block.timestamp + 5 hours);

        if (periodFinishInFuture) {
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector),
                abi.encode(block.timestamp + 1 days)
            );
        } else {
            vm.mockCall(
                gauge, abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector), abi.encode(block.timestamp)
            );
        }

        if (rewardPerTokenIncreased) {
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector),
                abi.encode(mockRewardPerToken + 10)
            );
        } else {
            vm.mockCall(
                gauge, abi.encodeWithSelector(IAerodromeGauge.rewardPerToken.selector), abi.encode(mockRewardPerToken)
            );
        }

        assertEq(calculator.safeTotalSupply(), 0);
        calculator.snapshot();
        if (periodFinishInFuture && rewardPerTokenIncreased) {
            assertEq(calculator.safeTotalSupply(), mockTotalSupply);
        } else {
            assertEq(calculator.safeTotalSupply(), 0);
        }
    }

    function test_RevertIf_SnapshotIfSpotPriceIsNotSafePriceSnapshot() public {
        successfulInitalize();
        mockDefaultData();
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector),
            abi.encode(1, 1, false)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsafePrice.selector, pool, 1, 1));
        calculator.snapshot();
    }

    function test_CurrentSucceedsIfSpotPriceIsNotSafePrice() public {
        successfulInitalize();
        mockDefaultData();
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector),
            abi.encode(1, 1, false)
        );
        calculator.current();
    }

    function runIncreaseIncentiveCreditsScenario() public returns (uint256 rewardPerTokenValue) {
        uint256 nbSnapshots = 36;
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);

        rewardPerTokenValue = 40_000_000_000_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14_000_000_000_000_000;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 8 hours;
            }

            rewardPerTokenValue += 5_000_000_000_000_000_000;
        }

        successfulInitalize();
        mockDefaultData();
        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        return rewardPerTokenValue;
    }

    function testIncreaseIncentiveCredits() public {
        runIncreaseIncentiveCreditsScenario();

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertEq(res.stakingIncentiveStats.incentiveCredits, calculator.MAX_CREDITS());
        assertGt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());
    }

    function testDecreaseIncentiveCreditsBecauseRewardTokenValueTooLow(uint256 nbSnapshots) public {
        uint256 rewardPerTokenValue = runIncreaseIncentiveCreditsScenario();
        rewardPerTokenValue += 5e18;

        setIncentivePrice(AERO, 1, 1);

        vm.assume(nbSnapshots < 10);
        vm.assume(nbSnapshots > 2);
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);
        uint256 hoursSinceDecayStart = 0;

        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14e15;
            totalSupply[i] = 18e18;
            rewardPerToken[i] = rewardPerTokenValue;
            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 8 hours;
            }
            hoursSinceDecayStart += time[i] / 1 hours;

            rewardPerTokenValue += 5e18;
        }

        assertGt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());
        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        assertLt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());

        uint256 expectedCredits =
            hoursSinceDecayStart > calculator.MAX_CREDITS() ? 0 : calculator.MAX_CREDITS() - hoursSinceDecayStart;
        IDexLSTStats.DexLSTStatsData memory res = calculator.current();

        assertEq(res.stakingIncentiveStats.incentiveCredits, expectedCredits);
    }

    function testFuzzDecreaseIncentiveCreditsBecauseRewardPerTokenStoredIncreasesTooSlowly(uint256 nbSnapshots)
        public
    {
        uint256 rewardPerTokenValue = runIncreaseIncentiveCreditsScenario();
        rewardPerTokenValue += 1e18;
        setIncentivePrice(AERO, 1e9, 1e9); // mock token to a more reasonable value for 18e18 total supply

        vm.assume(nbSnapshots < 10);
        vm.assume(nbSnapshots > 2);
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);
        uint256 hoursSinceDecayStart = 0;

        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14e15;
            totalSupply[i] = 18e18;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 8 hours;
            }
            hoursSinceDecayStart += time[i] / 1 hours;

            rewardPerTokenValue += 1e18;
        }

        assertGt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());
        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        assertLt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());

        uint256 expectedCredits =
            hoursSinceDecayStart > calculator.MAX_CREDITS() ? 0 : calculator.MAX_CREDITS() - hoursSinceDecayStart;

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertEq(res.stakingIncentiveStats.incentiveCredits, expectedCredits);
    }

    function testFuzzDecreaseIncentiveCreditsBecauseBecauseRewardRateTooLow(uint256 nbSnapshots) public {
        uint256 rewardPerTokenValue = runIncreaseIncentiveCreditsScenario();
        rewardPerTokenValue += 5_000_000_000_000_000_000;
        setIncentivePrice(AERO, 1e9, 1e9); // mock token to a more reasonable value for 18e18 totalSupply
        vm.assume(nbSnapshots < 10);
        vm.assume(nbSnapshots > 2);
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);
        uint256 hoursSinceDecayStart = 0;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 4e9; // very low reward rate
            totalSupply[i] = 18e18;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 8 hours;
            }
            hoursSinceDecayStart += time[i] / 1 hours;

            rewardPerTokenValue += 5e18;
        }

        assertGt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());
        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        assertLt(calculator.lastSnapshotTotalAPR(), calculator.NON_TRIVIAL_ANNUAL_RATE());

        uint256 expectedCredits =
            hoursSinceDecayStart > calculator.MAX_CREDITS() ? 0 : calculator.MAX_CREDITS() - hoursSinceDecayStart;

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertEq(res.stakingIncentiveStats.incentiveCredits, expectedCredits);
    }

    function testIncentiveAprShouldBeZeroIfBlockTimestampAfterPeriodFinish() public {
        create2StepsSnapshot();

        assertEq(calculator.lastSnapshotTotalAPR(), 1_752_000_000_000_000_000);

        vm.warp(block.timestamp + 25 hours);
        calculator.snapshot();
        vm.mockCall(gauge, abi.encodeWithSelector(IAerodromeGauge.periodFinish.selector), abi.encode(block.timestamp));
        vm.warp(block.timestamp + 5 hours);
        calculator.snapshot();
        assertEq(calculator.lastSnapshotTotalAPR(), 0);
    }
}
