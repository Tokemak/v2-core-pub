// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
/* solhint-disable func-name-mixedcase,contract-name-camelcase */
pragma solidity >=0.8.7;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Stats } from "src/stats/Stats.sol";
import { AuraCalculator } from "src/stats/calculators/AuraCalculator.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { AURA_MAINNET, AURA_BOOSTER } from "test/utils/Addresses.sol";
import { IBooster } from "src/interfaces/external/aura/IBooster.sol";

contract AuraCalculatorTest is Test {
    address internal underlyerStats;
    address internal pricingStats;
    address internal systemRegistry;
    address internal rootPriceOracle;

    address internal mainRewarder;
    address internal mainRewarderRewardToken;
    address internal extraRewarder1;
    address internal extraRewarder2;
    address internal extraRewarder3;
    address internal platformRewarder;
    address internal booster;

    AuraCalculator internal calculator;

    uint256 internal constant REWARD_PER_TOKEN = 1000;
    uint256 internal constant REWARD_RATE = 10_000;
    uint256 internal constant REWARD_TOKEN = 8 hours;
    uint256 internal constant PERIOD_FINISH_IN = 100 days;
    uint256 internal constant DURATION = 1 weeks;
    uint256 internal constant TOTAL_SUPPLY = 10e25; // 100m
    uint256 internal constant EXTRA_REWARD_LENGTH = 0;

    error InvalidScenario();

    function setUp() public {
        underlyerStats = vm.addr(1);
        pricingStats = vm.addr(2);
        systemRegistry = vm.addr(3);
        rootPriceOracle = vm.addr(4);

        mainRewarder = vm.addr(100); // AURA_REWARDER
        mainRewarderRewardToken = vm.addr(10_000);
        extraRewarder1 = vm.addr(101);
        extraRewarder2 = vm.addr(102);
        extraRewarder3 = vm.addr(103);
        platformRewarder = vm.addr(104);
        booster = vm.addr(105);

        vm.label(underlyerStats, "underlyerStats");
        vm.label(pricingStats, "pricingStats");
        vm.label(systemRegistry, "systemRegistry");
        vm.label(rootPriceOracle, "rootPriceOracle");
        vm.label(mainRewarder, "mainRewarder");
        vm.label(extraRewarder1, "extraRewarder1");
        vm.label(extraRewarder2, "extraRewarder2");
        vm.label(extraRewarder3, "extraRewarder3");
        vm.label(platformRewarder, "platformRewarder");
        vm.label(booster, "booster");

        // mock system registry
        vm.mockCall(
            systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector),
            abi.encode(rootPriceOracle)
        );

        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.accessController.selector), abi.encode(vm.addr(1000))
        );
        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.incentivePricing.selector), abi.encode(pricingStats)
        );

        // mock all prices to be 1
        vm.mockCall(rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector), abi.encode(1));
        vm.mockCall(pricingStats, abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector), abi.encode(1, 1));

        // set plateforme reward token (CVX) total supply
        vm.mockCall(platformRewarder, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(TOTAL_SUPPLY));

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

        vm.mockCall(underlyerStats, abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(data));

        calculator = new AuraCalculator(ISystemRegistry(systemRegistry), booster);
        calculator.initialize(mainRewarder, underlyerStats, platformRewarder);
    }

    function mockRewardRate(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardRate.selector), abi.encode(value));
    }

    function mockPeriodFinish(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.periodFinish.selector), abi.encode(value));
    }

    function mockDuration(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.duration.selector), abi.encode(value));
    }

    function mockRewardToken(address _rewarder, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardToken.selector), abi.encode(value));
    }

    function mockExtraRewardsLength(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(value));
    }

    function mockExtraRewards(address _rewarder, uint256 index, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, index), abi.encode(value));
    }

    function mockRewardPerToken(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardPerToken.selector), abi.encode(value));
    }

    function mockTotalSupply(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.totalSupply.selector), abi.encode(value));
    }

    function mockAsset(address _rewarder, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.stakingToken.selector), abi.encode(value));
    }

    function mockBoosterRewardMultiplierDen(address _booster, uint256 value) public {
        vm.mockCall(
            _booster, abi.encodeWithSelector(IBooster.REWARD_MULTIPLIER_DENOMINATOR.selector), abi.encode(value)
        );
    }

    function mockBoosterRewardMultiplier(address _booster, address _rewarder, uint256 value) public {
        vm.mockCall(
            _booster, abi.encodeWithSelector(IBooster.getRewardMultipliers.selector, _rewarder), abi.encode(value)
        );
    }

    function mockSimpleMainRewarder() public {
        mockRewardPerToken(mainRewarder, REWARD_PER_TOKEN);
        mockRewardRate(mainRewarder, REWARD_RATE);
        mockPeriodFinish(mainRewarder, block.timestamp + PERIOD_FINISH_IN);
        mockTotalSupply(mainRewarder, TOTAL_SUPPLY);
        mockRewardToken(mainRewarder, mainRewarderRewardToken);
        mockDuration(mainRewarder, DURATION);
        mockExtraRewardsLength(mainRewarder, EXTRA_REWARD_LENGTH);
        mockAsset(mainRewarder, vm.addr(1001));
        mockBoosterRewardMultiplierDen(booster, 1000);
        mockBoosterRewardMultiplier(booster, mainRewarder, 8000);
    }

    // mockMainRewarderWithExtraRewarder function
    function addMockExtraRewarder() public {
        mockExtraRewardsLength(mainRewarder, 1);
        mockExtraRewards(mainRewarder, 0, extraRewarder1);

        mockRewardPerToken(extraRewarder1, REWARD_PER_TOKEN);
        mockRewardRate(extraRewarder1, REWARD_RATE);
        mockPeriodFinish(extraRewarder1, block.timestamp + PERIOD_FINISH_IN);
        mockTotalSupply(extraRewarder1, TOTAL_SUPPLY);
        mockRewardToken(extraRewarder1, vm.addr(1000));
        mockDuration(extraRewarder1, DURATION);
        mockExtraRewardsLength(extraRewarder1, 0);
        mockAsset(extraRewarder1, vm.addr(1002));
    }

    function create2StepsSnapshot() internal {
        mockSimpleMainRewarder();
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();
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

        mockSimpleMainRewarder();
        for (uint256 i = 0; i < rewardRates.length; i++) {
            mockRewardRate(mainRewarder, rewardRates[i]);
            mockTotalSupply(mainRewarder, totalSupply[i]);
            mockRewardPerToken(mainRewarder, rewardPerToken[i]);

            calculator.snapshot();
            vm.warp(block.timestamp + time[i]);
        }
    }

    function create2StepsSnapshotWithTotalSupplyIncrease(uint256 moveForwardInTime) internal {
        mockSimpleMainRewarder();
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        mockTotalSupply(mainRewarder, TOTAL_SUPPLY + ((TOTAL_SUPPLY * 30) / 100));

        calculator.snapshot();

        vm.warp(block.timestamp + moveForwardInTime);
    }
}

contract ShouldSnapshot is AuraCalculatorTest {
    function test_ReturnsTrueIfNoSnapshotTakenYet() public {
        mockSimpleMainRewarder();
        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSnapshotTakenWithinInterval() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfExtraRewardsAdded() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        addMockExtraRewarder();

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfRewardRatesChangedMidProcess() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        mockRewardRate(mainRewarder, REWARD_RATE + 10);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfSnapshotTakenBeforeInterval() public {
        mockSimpleMainRewarder();

        assertTrue(calculator.shouldSnapshot());

        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSnapshotTakenWithin24Hours() public {
        create2StepsSnapshot();

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfNoSnapshotTakenIn24Hours() public {
        create2StepsSnapshot();

        vm.warp(block.timestamp + 25 hours);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfRewardPeriodFinished() public {
        create2StepsSnapshot();

        mockPeriodFinish(mainRewarder, block.timestamp - 1);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfRewardRateIsZero() public {
        create2StepsSnapshot();

        mockRewardRate(mainRewarder, 0);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfTotalSupplyIsZero() public {
        create2StepsSnapshot();

        mockTotalSupply(mainRewarder, 0);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSupplyDiffersBy5PctAndSnapshotTakenWithin8Hours() public {
        create2StepsSnapshotWithTotalSupplyIncrease(5 hours);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfSupplyDiffersBy5PctAndSnapshotTakenAfter8Hours() public {
        create2StepsSnapshotWithTotalSupplyIncrease(9 hours);

        assertTrue(calculator.shouldSnapshot());
    }
}

contract Snapshot is AuraCalculatorTest {
    function test_StartsSnapshotProcess() public {
        uint256 currentTime = block.timestamp;
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        assertTrue(calculator.lastSnapshotRewardPerToken(mainRewarder) == REWARD_PER_TOKEN + 1);
        assertTrue(calculator.lastSnapshotTimestamps(mainRewarder) == currentTime);
        assertTrue(calculator.safeTotalSupplies(mainRewarder) == 0);
    }

    function test_FinalizesSnapshotProcess() public {
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();

        // should reset the lastSnapshotRewardPerToken
        assertTrue(calculator.lastSnapshotRewardPerToken(mainRewarder) == 0);
        assertTrue(calculator.lastSnapshotTimestamps(mainRewarder) == block.timestamp);
    }
}

contract Current is AuraCalculatorTest {
    function test_FinalizesSnapshotProcess() public {
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();

        calculator.current();
    }

    function test_IncreaseIncentiveCredits() public {
        uint256 nbSnapshots = 6;
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);

        uint256 rewardPerTokenValue = 40_000_000_000_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14_000_000_000_000_000;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 5 hours;
            }

            rewardPerTokenValue += 5_000_000_000_000_000_000;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertTrue(res.stakingIncentiveStats.incentiveCredits == nbSnapshots);
        assertTrue(res.stakingIncentiveStats.rewardTokens.length == 2);
        assertTrue(res.stakingIncentiveStats.rewardTokens[0] == mainRewarderRewardToken);
        assertTrue(res.stakingIncentiveStats.rewardTokens[1] == platformRewarder);
        assertTrue(res.stakingIncentiveStats.periodFinishForRewards[0] == PERIOD_FINISH_IN + 1);
        assertTrue(res.stakingIncentiveStats.periodFinishForRewards[1] == PERIOD_FINISH_IN + 1);
    }

    function test_DecreaseIncentiveCredits() public {
        uint256 nbSnapshots = 24;
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);

        uint256 rewardPerTokenValue = 40_000_000_000_000_000_000;
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

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();

        // Ensure that the incentive credits have been increased
        assertTrue(res.stakingIncentiveStats.incentiveCredits == 24);

        // Decrease the incentive credits by decreasing the reward rate
        nbSnapshots = 3;
        rewardRates = new uint256[](nbSnapshots);
        totalSupply = new uint256[](nbSnapshots);
        rewardPerToken = new uint256[](nbSnapshots);
        time = new uint256[](nbSnapshots);

        uint256 rewardRatesValue = 1_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = rewardRatesValue;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // 24 hours of decay in 8 hours increments
            // last 8 hours of credit are burned in current()
            time[i] = 8 hours;

            rewardRatesValue -= 5_000_000;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        res = calculator.current();
        assertTrue(res.stakingIncentiveStats.incentiveCredits == 0);
    }
}
