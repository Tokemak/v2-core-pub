pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { MaverickCalculator } from "src/stats/calculators/MaverickCalculator.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IPoolPositionSlim } from "src/interfaces/external/maverick/IPoolPositionSlim.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */

// example boosted position
// https://app.mav.xyz/boosted-positions/0x4650c64a8136f7bc2616a524cb44cfb240e33a40?chain=1
contract MaverickCalculatorTest is Test {
    address internal underlyerStats;
    address internal pricingStats;
    address internal systemRegistry;
    address internal rootPriceOracle;

    address internal boostedRewarder;
    address internal boostedPosition;

    address internal incentiveToken0;
    address internal incentiveToken1;
    address internal incentiveToken2;
    address internal pool;

    MaverickCalculator internal calculator;

    uint256 internal constant REWARD_PER_TOKEN = 1000;
    uint256 internal constant REWARD_RATE = 10_000;
    uint256 internal constant DURATION = 1 weeks;
    // 18e24 is the safeTotalSupply calc when two snapshots of (rewardPerToken = 1000 + 10) in 5 hours
    uint256 internal constant TOTAL_SUPPLY = 18e24;
    uint256 internal constant START_TIMESTAMP = 1_705_173_443;
    uint256 private constant START_BLOCK = 19_000_000;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    error InvalidScenario();

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), START_BLOCK);
        vm.selectFork(mainnetFork);
        vm.warp(START_TIMESTAMP);

        underlyerStats = vm.addr(1);
        pricingStats = vm.addr(2);
        systemRegistry = vm.addr(3);
        rootPriceOracle = vm.addr(4);

        boostedRewarder = vm.addr(10);
        boostedPosition = vm.addr(11);
        pool = vm.addr(12);

        incentiveToken0 = vm.addr(100);
        incentiveToken1 = vm.addr(101);
        incentiveToken2 = vm.addr(102);

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
        // can be 1 or 1e18 the LP and Incentive Token Price scales cancel out in _computeApr
        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, true)
        );
        vm.mockCall(pricingStats, abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector), abi.encode(1, 1));

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
        vm.mockCall(boostedPosition, abi.encodeWithSelector(IPoolPositionSlim.pool.selector), abi.encode(pool));
        vm.mockCall(systemRegistry, abi.encodeWithSelector(ISystemRegistry.weth.selector), abi.encode(IWETH9(WETH)));
        // calculator = new MaverickCalculator(ISystemRegistry(systemRegistry));
        calculator = MaverickCalculator(Clones.clone(address(new MaverickCalculator(ISystemRegistry(systemRegistry)))));
    }

    function mockTotalSupply(uint256 value) public {
        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(value));
    }

    function mockRewardInfo(
        uint256[] memory finishAts,
        uint256[] memory rewardRates,
        uint256[] memory rewardPerTokenStoreds,
        IERC20[] memory rewardTokens
    ) internal {
        IReward.RewardInfo[] memory rewardInfo = new IReward.RewardInfo[](finishAts.length);

        for (uint256 i = 0; i < finishAts.length; i++) {
            rewardInfo[i] = IReward.RewardInfo(
                finishAts[i],
                0, // updatedAt is not used, keeping as 0
                rewardRates[i],
                rewardPerTokenStoreds[i],
                IERC20(rewardTokens[i])
            );
        }

        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IReward.rewardInfo.selector), abi.encode(rewardInfo));
    }

    function getDefaultValues()
        internal
        view
        returns (uint256, uint256[] memory, uint256[] memory, uint256[] memory, IERC20[] memory)
    {
        // include the 0ths slot in what gets returned
        uint256[] memory finishAts = new uint256[](3);
        finishAts[1] = uint256(START_TIMESTAMP + 7 days);
        finishAts[2] = uint256(START_TIMESTAMP + 7 days);

        uint256[] memory rewardRates = new uint256[](3);
        rewardRates[1] = REWARD_RATE;
        rewardRates[2] = REWARD_RATE;

        uint256[] memory rewardPerTokenStoreds = new uint256[](3);
        rewardPerTokenStoreds[1] = REWARD_PER_TOKEN;
        rewardPerTokenStoreds[2] = REWARD_PER_TOKEN;

        IERC20[] memory rewardTokens = new IERC20[](3);
        rewardTokens[1] = IERC20(incentiveToken0);
        rewardTokens[2] = IERC20(incentiveToken1);

        return (TOTAL_SUPPLY, finishAts, rewardRates, rewardPerTokenStoreds, rewardTokens);
    }

    function successfulInitialize() internal {
        bytes32[] memory depAprIds = new bytes32[](0);
        bytes memory initData = abi.encode(
            MaverickCalculator.InitData({
                underlyerStats: underlyerStats,
                boostedRewarder: boostedRewarder,
                boostedPosition: boostedPosition
            })
        );
        setRewardInfoAndTotalSupplyToDefault();
        calculator.initialize(depAprIds, initData);
    }

    function setRewardInfoAndTotalSupplyToDefault() internal {
        (
            uint256 totalSupply,
            uint256[] memory finishAts,
            uint256[] memory rewardRates,
            uint256[] memory rewardPerTokenStoreds,
            IERC20[] memory rewardTokens
        ) = getDefaultValues();

        mockRewardInfo(finishAts, rewardRates, rewardPerTokenStoreds, rewardTokens);
        mockTotalSupply(totalSupply);
    }

    function setRewardInfoAndTotalSupplyToDefaultWithOneRewardTokenDeleted(uint256 rewardTokenToDeleteIndex) internal {
        (
            uint256 totalSupply,
            uint256[] memory finishAts,
            uint256[] memory rewardRates,
            uint256[] memory rewardPerTokenStoreds,
            IERC20[] memory rewardTokens
        ) = getDefaultValues();

        finishAts[rewardTokenToDeleteIndex] = 0;
        rewardRates[rewardTokenToDeleteIndex] = 0;
        rewardPerTokenStoreds[rewardTokenToDeleteIndex] = 0;
        rewardTokens[rewardTokenToDeleteIndex] = IERC20(address(0));

        mockRewardInfo(finishAts, rewardRates, rewardPerTokenStoreds, rewardTokens);
        mockTotalSupply(totalSupply);
    }

    function create2StepsSnapshot() internal {
        successfulInitialize();
        calculator.snapshot();

        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken0), REWARD_PER_TOKEN + 1); // +1 for init flag
        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken1), REWARD_PER_TOKEN + 1); // +1 for init flag

        mockRewardPerTokenStoreds(1, REWARD_PER_TOKEN + 10);
        mockRewardPerTokenStoreds(2, REWARD_PER_TOKEN + 10);
        vm.warp(block.timestamp + 5 hours);

        assertTrue(calculator.shouldSnapshot());
        calculator.snapshot();

        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken0), 0);
        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken1), 0);
        assertEq(calculator.lastSnapshotRewardRates(incentiveToken0), REWARD_RATE);
        assertEq(calculator.lastSnapshotRewardRates(incentiveToken1), REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());
    }

    function mockRewardRate(uint256 slot, uint256 value) internal {
        IReward.RewardInfo[] memory priorRewardInfo = calculator.boostedRewarder().rewardInfo();
        IReward.RewardInfo memory toOverwrite = priorRewardInfo[slot];

        toOverwrite.rewardRate = value;
        priorRewardInfo[slot] = toOverwrite;

        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IReward.rewardInfo.selector), abi.encode(priorRewardInfo));
    }

    function mockFinishAt(uint256 slot, uint256 value) internal {
        IReward.RewardInfo[] memory priorRewardInfo = calculator.boostedRewarder().rewardInfo();
        IReward.RewardInfo memory toOverwrite = priorRewardInfo[slot];

        toOverwrite.finishAt = value;
        priorRewardInfo[slot] = toOverwrite;

        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IReward.rewardInfo.selector), abi.encode(priorRewardInfo));
    }

    function mockRewardToken(uint256 slot, address value) internal {
        IReward.RewardInfo[] memory priorRewardInfo = calculator.boostedRewarder().rewardInfo();
        IReward.RewardInfo memory toOverwrite = priorRewardInfo[slot];

        toOverwrite.rewardToken = IERC20(value);
        priorRewardInfo[slot] = toOverwrite;

        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IReward.rewardInfo.selector), abi.encode(priorRewardInfo));
    }

    function mockRewardPerTokenStoreds(uint256 slot, uint256 value) internal {
        IReward.RewardInfo[] memory priorRewardInfo = calculator.boostedRewarder().rewardInfo();
        IReward.RewardInfo memory toOverwrite = priorRewardInfo[slot];

        toOverwrite.rewardPerTokenStored = value;
        priorRewardInfo[slot] = toOverwrite;

        vm.mockCall(boostedRewarder, abi.encodeWithSelector(IReward.rewardInfo.selector), abi.encode(priorRewardInfo));
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

        for (uint256 i = 0; i < rewardRates.length; i++) {
            mockRewardRate(1, rewardRates[i]);
            mockTotalSupply(totalSupply[i]);
            mockRewardPerTokenStoreds(1, rewardPerToken[i]);

            calculator.snapshot();
            vm.warp(block.timestamp + time[i]);
        }
    }
}

contract ShouldSnapshot is MaverickCalculatorTest {
    /// @dev if there have been no snapshots, take a snapshot
    function test_ReturnsTrueIfNoSnapshotTakenYet() public {
        successfulInitialize();
        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfRewardRatesChangedMidProcess() public {
        successfulInitialize();
        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(1, REWARD_RATE + 1);
        assertTrue(calculator.shouldSnapshot());

        setRewardInfoAndTotalSupplyToDefault();

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(2, REWARD_RATE - 1);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev take the finalization snapshot 3 hours after the first snapshot
    function test_ReturnsTrueIfSnapshotTakenBeforeInterval() public {
        successfulInitialize();

        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 3 hours - 1);
        assertFalse(calculator.shouldSnapshot());

        vm.warp(block.timestamp + 1);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev if rewardRate is 0 don't trigger a new snapshot
    function testFuzz_ReturnsFalseIfRewardRateIsZeroAnyTimeInFuture(uint256 someSeconds) public {
        vm.assume(someSeconds < 100 days);

        create2StepsSnapshot();
        vm.warp(block.timestamp + 25 hours);
        assertTrue(calculator.shouldSnapshot());

        mockRewardRate(1, 0);
        mockRewardRate(2, 0);
        assertFalse(calculator.shouldSnapshot());
        vm.warp(block.timestamp + someSeconds);

        assertFalse(calculator.shouldSnapshot());
    }

    /// @dev don't trigger a snapshot if all the reward tokens have expired
    function test_ReturnsFalseIfFinishAtExpired() public {
        create2StepsSnapshot();
        vm.warp(block.timestamp + 25 hours);
        assertTrue(calculator.shouldSnapshot());
        mockFinishAt(1, block.timestamp - 1);
        mockFinishAt(2, block.timestamp - 1);
        assertFalse(calculator.shouldSnapshot());
    }

    /// @dev don't trigger a snapshot too early
    function test_ReturnsFalseIfSnapshotTakenWithin24Hours() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());
        vm.warp(block.timestamp + 23 hours);
        assertFalse(calculator.shouldSnapshot());
    }

    /// @dev if a snapshot has not happend within 24 hours take a new one
    function test_ReturnsTrueIfNoSnapshotTakenIn24Hours() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());
        vm.warp(block.timestamp + 25 hours);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev if total supply drop to 0, trigger a snapshot
    function test_ReturnsTrueIfTotalSupplyIsZero() public {
        create2StepsSnapshot();
        assertFalse(calculator.shouldSnapshot());
        mockTotalSupply(0);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev if a token's reward rate deviates by more than 5% trigger a new snapshot
    function test_ReturnsTrueIfRewardRatesChangeByMoreThan5Percent() public {
        create2StepsSnapshot();

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(1, (REWARD_RATE * 105 / 100) + 1);
        assertTrue(calculator.shouldSnapshot());

        mockRewardRate(1, REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(1, ((REWARD_RATE * 95) / 100) - 1);
        assertTrue(calculator.shouldSnapshot());
        mockRewardRate(1, REWARD_RATE);

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(2, (REWARD_RATE * 105 / 100) + 1);
        assertTrue(calculator.shouldSnapshot());

        mockRewardRate(2, REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(2, ((REWARD_RATE * 95) / 100) - 1);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev if a token's reward rate deviates by less than 5% don't trigger a new snapshot
    function test_ReturnsFalseIfRewardRatesChangeByLessThan5Percent() public {
        create2StepsSnapshot();

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(1, (REWARD_RATE * 105 / 100) - 1);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(1, REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(1, ((REWARD_RATE * 96) / 100));
        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(1, REWARD_RATE);

        assertFalse(calculator.shouldSnapshot());
        mockRewardRate(2, (REWARD_RATE * 105 / 100) - 1);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(2, REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());

        mockRewardRate(2, ((REWARD_RATE * 96) / 100));
        assertFalse(calculator.shouldSnapshot());
    }

    /// @dev if the total supply deviates by more than 5% don't trigger a new snapshot
    function test_ReturnsTrueIfTotalSupplyDiffersFromSafeTotalSupplyByMoreThan5PercentAfter6Hours() public {
        create2StepsSnapshot();
        vm.warp(block.timestamp + 6 hours + 1);
        assertFalse(calculator.shouldSnapshot());
        mockTotalSupply((TOTAL_SUPPLY * 94) / 100);
        assertTrue(calculator.shouldSnapshot());

        setRewardInfoAndTotalSupplyToDefault();

        assertFalse(calculator.shouldSnapshot());
        mockTotalSupply((TOTAL_SUPPLY * 106) / 100);
        assertTrue(calculator.shouldSnapshot());
    }

    /// @dev if the total supply deviates by less than 5% don't trigger a new snapshot
    function test_ReturnFalseIfTotalSupplyDiffersFromSafeTotalSupplyBylessThan5PercentAfter6Hours() public {
        create2StepsSnapshot();
        vm.warp(block.timestamp + 6 hours + 1);

        assertFalse(calculator.shouldSnapshot());
        mockTotalSupply(TOTAL_SUPPLY * 96 / 100);
        assertFalse(calculator.shouldSnapshot());

        setRewardInfoAndTotalSupplyToDefault();

        assertFalse(calculator.shouldSnapshot());
        mockTotalSupply(TOTAL_SUPPLY * 104 / 100);
        assertFalse(calculator.shouldSnapshot());
    }
}

contract Snapshot is MaverickCalculatorTest {
    /// @dev make sure that values match what is expected after the first snapshot
    function test_StartSnapshotProcess() public {
        uint256 currentTime = block.timestamp;
        successfulInitialize();

        calculator.snapshot();

        assertTrue(calculator.lastSnapshotRewardPerTokens(incentiveToken0) == REWARD_PER_TOKEN + 1);
        assertTrue(calculator.lastSnapshotTimestamps(incentiveToken0) == currentTime);
        assertTrue(calculator.safeTotalSupplies(incentiveToken0) == 0);

        assertTrue(calculator.lastSnapshotRewardPerTokens(incentiveToken1) == REWARD_PER_TOKEN + 1);
        assertTrue(calculator.lastSnapshotTimestamps(incentiveToken1) == currentTime);
        assertTrue(calculator.safeTotalSupplies(incentiveToken1) == 0);
    }

    /// @dev make sure that the snapshot finalization process behaves like expected
    function test_FinalizesSnapshotProcess() public {
        successfulInitialize();

        calculator.snapshot();

        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();

        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken0), 0);
        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken1), 0);

        assertEq(calculator.lastSnapshotTimestamps(incentiveToken0), block.timestamp);
        assertEq(calculator.lastSnapshotTimestamps(incentiveToken1), block.timestamp);

        assertEq(calculator.safeTotalSupplies(incentiveToken0), 0); // because rewardPerToken doesn't change expect 0
        assertEq(calculator.safeTotalSupplies(incentiveToken1), 0);
    }

    /// @dev if a rewardToken does not have any rewards accumulate, the safe total supply should not change.
    function test_SafeTotalSupplyProperlyUpdatedAfterSnapshotWithNoRewardsIssued() public {
        create2StepsSnapshot();

        assertEq(calculator.safeTotalSupplies(incentiveToken0), TOTAL_SUPPLY);
        assertEq(calculator.safeTotalSupplies(incentiveToken1), TOTAL_SUPPLY);
        vm.warp(block.timestamp + 25 hours);
        mockRewardPerTokenStoreds(1, REWARD_PER_TOKEN + 100);
        mockRewardPerTokenStoreds(2, REWARD_PER_TOKEN + 200);
        calculator.snapshot();

        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken0), REWARD_PER_TOKEN + 100 + 1);
        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken1), REWARD_PER_TOKEN + 200 + 1); // init flag

        assertEq(calculator.safeTotalSupplies(incentiveToken0), TOTAL_SUPPLY);
        assertEq(calculator.safeTotalSupplies(incentiveToken1), TOTAL_SUPPLY);
        vm.warp(block.timestamp + 5 hours);

        mockRewardPerTokenStoreds(2, REWARD_PER_TOKEN + 300);
        calculator.snapshot();

        // because rewards have not accured, we expect safe totalSupply not to change. (diff == 0)
        assertEq(calculator.safeTotalSupplies(incentiveToken0), TOTAL_SUPPLY);
        // because rewards have accured, we expect the safeTotalSupply to be different (diff > 0)
        assertNotEq(calculator.safeTotalSupplies(incentiveToken1), TOTAL_SUPPLY);
    }

    /// @dev snapshot() should revert if the safe lp token price is not near enough to the spot
    function test_SnapshotFailsIfLPTokenSafeIsNotSpotPrice() public {
        successfulInitialize();
        assertTrue(calculator.shouldSnapshot());
        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, false)
        );

        vm.expectRevert();
        calculator.snapshot();
    }

    /// @dev ensure that snapshot() won't underflow if we don't snapshot for a protracted period
    /// this fails when days without snapshot == 99999
    function testFuzz_MaverickIncentiveCreditsDoesNotUnderflowWhenMissingSnapshotForManyDays(
        uint256 daysWithoutSnapshot
    ) public {
        vm.assume(daysWithoutSnapshot < 10_000);
        vm.assume(daysWithoutSnapshot > 21);
        successfulInitialize();

        mockFinishAt(1, block.timestamp + 100_000 days);

        uint256 nbSnapshots = 2; // 1 day
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

        // increase rewardPerToken enough that the destination will still get incentive credits
        rewardPerTokenValue += 2 * daysWithoutSnapshot * 5_000_000_000_000_000_000;
        mockRewardPerTokenStoreds(1, rewardPerTokenValue);
        vm.warp(block.timestamp + (daysWithoutSnapshot * (1 days)));
        calculator.snapshot();
        IDexLSTStats.DexLSTStatsData memory cur = calculator.current();
        assertEq(cur.stakingIncentiveStats.incentiveCredits, calculator.MAX_CREDITS());
    }

    function test_NoUnderFlowIfRewardsExpireAndAreAddedBackWithALowerRewardPerTokenMidSnapshot() public {
        successfulInitialize();
        calculator.snapshot(); // snapshot 1
        mockRewardPerTokenStoreds(1, REWARD_PER_TOKEN - 10);
        mockRewardPerTokenStoreds(2, REWARD_PER_TOKEN - 10);
        vm.warp(block.timestamp + 5 hours);
        // each token finishAt is still in the future
        calculator.snapshot(); // snapshot 2 is a shouldRestartSnapshot()

        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken0), REWARD_PER_TOKEN - 10 + 1);
        assertEq(calculator.lastSnapshotRewardPerTokens(incentiveToken1), REWARD_PER_TOKEN - 10 + 1);
        assertEq(calculator.lastSnapshotRewardRates(incentiveToken0), REWARD_RATE);
        assertEq(calculator.lastSnapshotRewardRates(incentiveToken1), REWARD_RATE);
        assertFalse(calculator.shouldSnapshot());
    }
}

contract Current is MaverickCalculatorTest {
    /// @dev in the normal case, make sure current() doesn't revert
    function test_FinalizesSnapshotProcess() public {
        create2StepsSnapshot();
        calculator.current();
    }

    /// @dev make sure incentive credits increase and decrease as expected.
    function test_IncreaseAndDecreaseIncentiveCredits() public {
        successfulInitialize();
        mockFinishAt(1, block.timestamp + 100 days);

        uint256 nbSnapshots = 28; // 14 days to get to the max credits
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
        assertEq(res.stakingIncentiveStats.incentiveCredits, calculator.MAX_CREDITS()); // 168

        // Decrease the incentive credits by not accuring rewards between snapshot
        nbSnapshots = 3 * 7; // 3 snapshots a day for 7 days.
        rewardRates = new uint256[](nbSnapshots);
        totalSupply = new uint256[](nbSnapshots);
        rewardPerToken = new uint256[](nbSnapshots);
        time = new uint256[](nbSnapshots);

        uint256 rewardRatesValue = 1_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = rewardRatesValue;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue; // constant, meaning between snapshots no rewards accrue.
            time[i] = 8 hours;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        res = calculator.current();
        assertEq(res.stakingIncentiveStats.incentiveCredits, 0);
    }

    /// @dev if one of the reward tokens is addr(0) the associated annualizedRewardAmounts and rewardTokens should be 0
    function test_CurrentStakingDataIs0IfRewardTokenIsAddress0() public {
        create2StepsSnapshot();
        IDexLSTStats.DexLSTStatsData memory res = calculator.current();

        assertEq(res.stakingIncentiveStats.rewardTokens[0], incentiveToken0);
        assertEq(res.stakingIncentiveStats.annualizedRewardAmounts[0], 315_360_000_000);
        assertEq(res.stakingIncentiveStats.periodFinishForRewards[0], START_TIMESTAMP + 7 days);

        mockRewardToken(1, address(0));
        res = calculator.current();
        assertEq(res.stakingIncentiveStats.rewardTokens[0], address(0));
        assertEq(res.stakingIncentiveStats.annualizedRewardAmounts[0], 0);
        assertEq(res.stakingIncentiveStats.periodFinishForRewards[0], 0);
    }

    /// @dev Current() should revert if the spot LP token price is not safe
    function test_CurrentFailsIfSafeIsNotSpotPrice() public {
        successfulInitialize();
        calculator.snapshot();
        calculator.current();
        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, false)
        );
        vm.expectRevert();
        calculator.current();
    }

    function test_safeTotalSupplyIsNotZeroIfOneTokenExpiredAndTheOtherRemoved() public {
        successfulInitialize();
        calculator.snapshot();
        vm.warp(block.timestamp + 5 hours);
        mockRewardPerTokenStoreds(1, REWARD_PER_TOKEN + 10);
        calculator.snapshot();
        IDexLSTStats.DexLSTStatsData memory cur = calculator.current();
        assertEq(cur.stakingIncentiveStats.safeTotalSupply, TOTAL_SUPPLY);
        uint256 currentTime = block.timestamp + 7 days;
        vm.warp(currentTime);
        // increased from last time so some rewards, but it is currently expired
        mockRewardPerTokenStoreds(1, REWARD_PER_TOKEN + 20);
        mockFinishAt(1, currentTime - 1);

        // delete the rewardToken at slot 2 by setting all the returned values to 0
        mockFinishAt(2, 0);
        mockRewardPerTokenStoreds(2, 0);
        mockRewardRate(2, 0);
        mockRewardToken(2, address(0));

        cur = calculator.current();
        assertEq(cur.stakingIncentiveStats.safeTotalSupply, TOTAL_SUPPLY);
    }
}
