// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { Errors } from "src/utils/Errors.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { Stats } from "src/stats/Stats.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";

abstract contract IncentiveCalculatorBase is
    SystemComponent,
    SecurityBase,
    Initializable,
    IDexLSTStats,
    IStatsCalculator
{
    IDexLSTStats public underlyerStats;
    IBaseRewardPool public rewarder;
    address public platformToken; // like cvx

    /// @dev rewarder token address => uint256 safeTotalSupply
    mapping(address => uint256) public safeTotalSupplies;

    /// @dev rewarder token address => uint256 last snapshot timestamp
    mapping(address => uint256) public lastSnapshotTimestamps;

    /// @dev rewarder token address => uint256 last snapshot reward per token
    mapping(address => uint256) public lastSnapshotRewardPerToken;

    /// @dev rewarder token address => uint256 last snapshot reward rate
    mapping(address => uint256) public lastSnapshotRewardRate;

    /// @dev Last time total APR was recorded.
    uint256 public lastSnapshotTotalAPR;

    /// @dev Last time an incentive was recorded or distributed.
    uint256 public lastIncentiveTimestamp;

    /// @dev Last time an non trivial incentive was recorded or distributed.
    uint256 public decayInitTimestamp;

    /// @dev State variable to indicate non trivial incentive APR was measured last snapshot.
    bool public decayState;

    /// @dev Incentive credits balance before decay
    uint8 public incentiveCredits;

    /// @dev Interval between two consecutive snapshot steps during the snapshot process.
    uint256 public constant SNAPSHOT_INTERVAL = 4 hours;

    /// @dev Non-trivial annual rate set at 0.5% (in fixed point format 1e18 = 1).
    uint256 public constant NON_TRIVIAL_ANNUAL_RATE = 5e15;

    /// @dev Duration after which a price/data becomes stale.
    uint40 public constant PRICE_STALE_CHECK = 12 hours;

    /// @dev Cap on allowable credits in the system.
    uint8 public constant MAX_CREDITS = 48;

    /// @dev The APR Id
    bytes32 private _aprId;

    /// @dev Enum representing the snapshot status for a given rewarder.
    enum SnapshotStatus {
        noSnapshot, // Indicates that no snapshot has been taken yet for the rewarder.
        tooSoon, // Indicates that it's too soon to take another snapshot since the last one.
        shouldFinalize, // Indicates that the conditions are met for finalizing a snapshot.
        shouldRestart // Indicates that the conditions are met for restarting a snapshot.

    }

    struct InitData {
        address rewarder;
        address underlyerStats;
        address platformToken;
    }

    // Custom error for handling unexpected snapshot statuses
    error InvalidSnapshotStatus();

    event IncentiveSnapshot(
        uint256 totalApr,
        uint256 incentiveCredits,
        uint256 lastIncentiveTimestamp,
        bool decayState,
        uint256 decayInitTimestamp
    );

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes calldata initData) public virtual override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.rewarder, "rewarder");
        Errors.verifyNotZero(decodedInitData.underlyerStats, "underlyerStats");
        Errors.verifyNotZero(decodedInitData.platformToken, "platformToken");

        // slither-disable-start missing-zero-check
        rewarder = IBaseRewardPool(decodedInitData.rewarder);
        underlyerStats = IDexLSTStats(decodedInitData.underlyerStats);
        platformToken = decodedInitData.platformToken;
        // slither-disable-end missing-zero-check

        lastIncentiveTimestamp = block.timestamp;
        decayInitTimestamp = block.timestamp;

        decayState = false;

        _aprId = keccak256(abi.encode("incentive", platformToken, decodedInitData.rewarder));
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return platformToken;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IDexLSTStats
    function current() external returns (DexLSTStatsData memory dexLSTStatsData) {
        // Fetch base stats
        DexLSTStatsData memory data = underlyerStats.current();

        uint256 extraRewardsLength = rewarder.extraRewardsLength();
        // we add 2 to the length to account for the main reward and platform reward
        uint256 totalRewardsLength = extraRewardsLength + 2;
        uint8 currentCredits = incentiveCredits;

        address[] memory rewardTokens = new address[](totalRewardsLength);
        uint256[] memory safeTotalSupply = new uint256[](totalRewardsLength);
        uint256[] memory annualizedRewardAmounts = new uint256[](totalRewardsLength);
        uint40[] memory periodFinishForRewards = new uint40[](totalRewardsLength);

        // Determine if incentive credits earned should continue to be decayed
        if (decayState) {
            uint256 totalAPR = _computeTotalAPR();

            // Apply additional decay if APR is within tolerance
            // slither-disable-next-line incorrect-equality
            if ((totalAPR == 0) || totalAPR < (lastSnapshotTotalAPR + (lastSnapshotTotalAPR / 20))) {
                // slither-disable-start timestamp
                uint256 hoursPassed = (block.timestamp - decayInitTimestamp) / 3600;
                if (hoursPassed > 0) {
                    currentCredits = _decayCredits(incentiveCredits, hoursPassed);
                }
                // slither-disable-end timestamp
            }
        }

        // Compute main reward statistics
        (uint256 safeSupply, address rewardToken, uint256 annualizedReward, uint256 periodFinish) =
            _getStakingIncentiveStats(rewarder, false);

        // Store main reward stats
        safeTotalSupply[0] = safeSupply;
        rewardTokens[0] = rewardToken;
        annualizedRewardAmounts[0] = annualizedReward;
        periodFinishForRewards[0] = uint40(periodFinish);

        // Compute platform reward statistics
        safeTotalSupply[1] = safeSupply;
        rewardTokens[1] = platformToken;
        annualizedRewardAmounts[1] = getPlatformTokenMintAmount(platformToken, annualizedReward);
        periodFinishForRewards[1] = uint40(periodFinish);

        // Loop through and compute stats for each extra rewarder
        for (uint256 i = 0; i < extraRewardsLength; ++i) {
            IBaseRewardPool extraReward = IBaseRewardPool(rewarder.extraRewards(i));
            (safeSupply, rewardToken, annualizedReward, periodFinish) = _getStakingIncentiveStats(extraReward, true);

            // Store stats for the current extra reward
            rewardTokens[i + 2] = rewardToken;
            annualizedRewardAmounts[i + 2] = annualizedReward;
            periodFinishForRewards[i + 2] = uint40(periodFinish);
            safeTotalSupply[i + 2] += safeSupply;
        }

        // Compile aggregated data into the result struct
        data.stakingIncentiveStats = StakingIncentiveStats({
            safeTotalSupply: safeTotalSupply[0], // supply across all rewarders
            rewardTokens: rewardTokens,
            annualizedRewardAmounts: annualizedRewardAmounts,
            periodFinishForRewards: periodFinishForRewards,
            incentiveCredits: currentCredits
        });

        return data;
    }

    /**
     * @notice Determines if a snapshot is needed for the main rewarder or any of the extra rewarders.
     * @dev _shouldSnapshot returns true if more than 24 hours passed since the last snapshot.
     *  Incentive credits needs to be updated at least once every 24 hours which is covered by the above check.
     * @return true if any of the main or extra rewarders require a snapshot, otherwise false.
     */
    function shouldSnapshot() public view returns (bool) {
        // Check if the main rewarder needs a snapshot
        (uint256 rewardRate, uint256 totalSupply, uint256 periodFinish) = _getRewardPoolMetrics(address(rewarder));
        if (_shouldSnapshot(address(rewarder), rewardRate, periodFinish, totalSupply)) return true;

        // Determine the number of extra rewarders
        uint256 extraRewardsLength = rewarder.extraRewardsLength();

        // Iterate through extra rewarders to check if any of them need a snapshot
        for (uint256 i = 0; i < extraRewardsLength; ++i) {
            address extraRewarder = rewarder.extraRewards(i);
            (rewardRate, totalSupply, periodFinish) = _getRewardPoolMetrics(extraRewarder);
            if (_shouldSnapshot(extraRewarder, rewardRate, periodFinish, totalSupply)) return true;
        }

        // No rewarder requires a snapshot
        return false;
    }

    function snapshot() external {
        // Record a new snapshot of total APR across all rewarders
        // Also, triggers a new snapshot or finalize snapshot for total supply across all the rewarders
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
        lastSnapshotTotalAPR = _computeTotalAPR();
        uint8 currentCredits = incentiveCredits;
        uint256 elapsedTime = block.timestamp - lastIncentiveTimestamp;

        // If APR is above a threshold and credits are below the cap and 1 day has passed since the last update
        // slither-disable-next-line timestamp
        if (lastSnapshotTotalAPR >= NON_TRIVIAL_ANNUAL_RATE && currentCredits < MAX_CREDITS && elapsedTime >= 1 days) {
            // If APR is above a threshold, increment credits based on time elapsed
            // Only give credit for whole days, so divide-before-multiply is desired
            // slither-disable-next-line divide-before-multiply
            uint8 credits = uint8(2 * (elapsedTime / 1 days)); // 2 credits for each day
            // Increment credits, but cap at MAX_CREDITS
            incentiveCredits = uint8(Math.min(currentCredits + credits, MAX_CREDITS));
            // Update the last incentive timestamp to the current block's timestamp
            lastIncentiveTimestamp = block.timestamp;
            decayState = false;
        } else if (lastSnapshotTotalAPR >= NON_TRIVIAL_ANNUAL_RATE) {
            decayState = false;
        } else if (lastSnapshotTotalAPR < NON_TRIVIAL_ANNUAL_RATE) {
            // Set to decay incentive credits state since APR is 0 or near 0
            if (!decayState) {
                decayState = true;
                decayInitTimestamp = block.timestamp;
            } else {
                // If APR is below a threshold, decay credits based on time elapsed
                // slither-disable-start timestamp
                uint256 hoursPassed = (block.timestamp - decayInitTimestamp) / 3600;
                // slither-disable-end timestamp
                if (hoursPassed > 0 && decayState) {
                    incentiveCredits = _decayCredits(currentCredits, hoursPassed);

                    // Update the incentive decay init timestamp to current timestamp
                    decayInitTimestamp = block.timestamp;
                }
            }
            // Update the last incentive timestamp to the current block's timestamp
            lastIncentiveTimestamp = block.timestamp;
        }

        // slither-disable-next-line reentrancy-events
        emit IncentiveSnapshot(
            lastSnapshotTotalAPR, incentiveCredits, lastIncentiveTimestamp, decayState, decayInitTimestamp
        );
    }

    /**
     * @notice Determines the snapshot status for a given rewarder.
     * @param _rewarder The address of the rewarder for which to check the snapshot status.
     * @param rewardRate The current reward rate for the rewarder.
     * @return The snapshot status for the given rewarder, based on the last snapshot and current block time.
     */
    function _snapshotStatus(address _rewarder, uint256 rewardRate) internal view returns (SnapshotStatus) {
        if (lastSnapshotRewardPerToken[_rewarder] == 0) {
            return SnapshotStatus.noSnapshot;
        }

        if (rewardRate != lastSnapshotRewardRate[_rewarder] && lastSnapshotRewardRate[_rewarder] != 0) {
            // lastSnapshotRewardRate[_rewarder] can be zero if the rewarder was just added
            return SnapshotStatus.shouldRestart;
        }

        // slither-disable-next-line timestamp
        if (block.timestamp < lastSnapshotTimestamps[_rewarder] + SNAPSHOT_INTERVAL) {
            return SnapshotStatus.tooSoon;
        }

        return SnapshotStatus.shouldFinalize;
    }

    /**
     * @notice Determines whether a snapshot should be taken for the specified rewarder.
     * @param _rewarder The address of the rewarder to check.
     * @param _rewardRate The current reward rate for the rewarder.
     * @param _totalSupply The current total supply staked with the rewarder.
     * @return True if a snapshot should be taken, false otherwise.
     */
    function _shouldSnapshot(
        address _rewarder,
        uint256 _rewardRate,
        uint256 _periodFinish,
        uint256 _totalSupply
    ) internal view returns (bool) {
        SnapshotStatus status = _snapshotStatus(_rewarder, _rewardRate);

        // If the status indicates we should finalize a snapshot, return true.
        if (status == SnapshotStatus.shouldFinalize || status == SnapshotStatus.shouldRestart) return true;

        // If it's too soon to take another snapshot, return false.
        if (status == SnapshotStatus.tooSoon) return false;

        uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamps[_rewarder];

        // If more than 24 hours passed since the last snapshot, take another one.
        // slither-disable-next-line timestamp
        if (timeBetweenSnapshots > 24 hours) return true;

        // No further snapshots are needed if reward rate is zero.
        if (_rewardRate == 0) return false;

        // No further snapshots are needed after the period finishes.
        // slither-disable-next-line timestamp
        if (block.timestamp > _periodFinish) return false;

        // Snapshot if there's no supply and still time left in the period.
        if (_totalSupply == 0) return true;

        // if _rewardRate differs by more than 5% from the last snapshot reward rate, take another snapshot.
        if (_differsByMoreThanFivePercent(lastSnapshotRewardRate[_rewarder], _rewardRate)) {
            return true;
        }

        uint256 safeTotalSupply = safeTotalSupplies[_rewarder];

        // If the staked supply deviates by more than 5% from the safe supply and 8 hours have passed since
        // the last snapshot, take another snapshot.
        // slither-disable-next-line timestamp
        if (_differsByMoreThanFivePercent(safeTotalSupply, _totalSupply) && timeBetweenSnapshots > 8 hours) {
            return true;
        }

        return false;
    }

    /**
     * @dev Performs a snapshot on the given rewarder's state.
     * This function assumes it's being called within the context of a _shouldSnapshot() conditional check.
     *
     * @param _rewarder Address of the rewarder for which the snapshot will be performed.
     * @param totalSupply The total supply of tokens for the rewarder.
     * @param rewardRate The current reward rate for the rewarder.
     */
    function _snapshot(address _rewarder, uint256 totalSupply, uint256 rewardRate) internal {
        if (totalSupply == 0) {
            safeTotalSupplies[_rewarder] = 0;
            lastSnapshotRewardPerToken[_rewarder] = 0;
            lastSnapshotTimestamps[_rewarder] = block.timestamp;
            return;
        }

        SnapshotStatus status = _snapshotStatus(_rewarder, rewardRate);
        uint256 rewardPerToken = IBaseRewardPool(_rewarder).rewardPerToken();

        // Initialization: When no snapshot exists, start a new snapshot.
        // Restart: If the reward rate changed, restart the snapshot process.
        if (status == SnapshotStatus.noSnapshot || status == SnapshotStatus.shouldRestart) {
            // Increase by one to ensure 0 is only used as an uninitialized value flag.
            lastSnapshotRewardPerToken[_rewarder] = rewardPerToken + 1;
            lastSnapshotRewardRate[_rewarder] = rewardRate;
            lastSnapshotTimestamps[_rewarder] = block.timestamp;
            return;
        }

        // Finalization: If a snapshot exists, finalize by calculating the reward accrued
        // since initialization, then reset the snapshot state.
        if (status == SnapshotStatus.shouldFinalize) {
            uint256 lastSnapshotTimestamp = lastSnapshotTimestamps[_rewarder];
            uint256 lastRewardPerToken = lastSnapshotRewardPerToken[_rewarder];
            // Subtract one, added during initialization, to ensure 0 is only used as an uninitialized value flag.
            uint256 diff = rewardPerToken - (lastRewardPerToken - 1);

            uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamp;

            safeTotalSupplies[_rewarder] = diff == 0 ? 0 : rewardRate * timeBetweenSnapshots * 1e18 / diff;
            lastSnapshotRewardPerToken[_rewarder] = 0;
            lastSnapshotTimestamps[_rewarder] = block.timestamp;

            return;
        }

        // It shouldn't be possible to reach this point.
        revert InvalidSnapshotStatus();
    }

    /**
     * @dev Computes staking incentive statistics for a given rewarder.
     *
     * @param _rewarder The rewarder contract for which the stats will be computed.
     * @param isExtraReward The flag to indicate the type of rewarder.
     * @return safeTotalSupply The total supply for the rewarder.
     * @return rewardToken The address of the reward token used by the rewarder.
     * @return annualizedRewardAmount The annual equivalent of the reward rate.
     * @return periodFinishForReward The timestamp when the reward period ends for the rewarder.
     */
    function _getStakingIncentiveStats(
        IBaseRewardPool _rewarder,
        bool isExtraReward
    )
        internal
        view
        returns (
            uint256 safeTotalSupply,
            address rewardToken,
            uint256 annualizedRewardAmount,
            uint256 periodFinishForReward
        )
    {
        rewardToken = isExtraReward ? resolveRewardToken(address(_rewarder)) : address(_rewarder.rewardToken());

        if (rewardToken != address(0)) {
            periodFinishForReward = _rewarder.periodFinish();

            uint256 rewardRate = _rewarder.rewardRate();

            annualizedRewardAmount = rewardRate * Stats.SECONDS_IN_YEAR;
            safeTotalSupply = safeTotalSupplies[address(_rewarder)];

            return (safeTotalSupply, rewardToken, annualizedRewardAmount, uint40(periodFinishForReward));
        }
    }

    /**
     * @dev Decays credits based on the elapsed time and reward rate.
     * Credits decay when the current time is past the reward period finish time
     * or when the reward rate is zero.
     *
     * @param currentCredits The current amount of credits.
     * @return The adjusted amount of credits after potential decay.
     */
    function _decayCredits(uint8 currentCredits, uint256 hoursPassed) internal pure returns (uint8) {
        // slither-disable-start timestamp
        currentCredits = uint8((hoursPassed > currentCredits) ? 0 : currentCredits - hoursPassed);
        // slither-disable-end timestamp

        return currentCredits;
    }

    /**
     * @notice Checks if the difference between two values is more than 5%.
     * @param value1 The first value.
     * @param value2 The second value.
     * @return A boolean indicating if the difference between the two values is more than 5%.
     */
    function _differsByMoreThanFivePercent(uint256 value1, uint256 value2) public pure returns (bool) {
        if (value1 > value2) {
            return value1 > (value2 + (value2 / 20)); // value2 / 20 represents 5% of value2
        } else {
            return value2 > (value1 + (value1 / 20)); // value1 / 20 represents 5% of value1
        }
    }

    function _getIncentivePrice(address _token) internal view returns (uint256) {
        IIncentivesPricingStats pricingStats = systemRegistry.incentivePricing();
        (uint256 fastPrice, uint256 slowPrice) = pricingStats.getPrice(_token, PRICE_STALE_CHECK);
        return Math.min(fastPrice, slowPrice);
    }

    function _getPriceInEth(address _token) internal returns (uint256) {
        // the price oracle handles reentrancy issues
        return systemRegistry.rootPriceOracle().getPriceInEth(_token);
    }

    function _getRewardPoolMetrics(address _rewarder)
        internal
        view
        returns (uint256 rewardRate, uint256 totalSupply, uint256 periodFinish)
    {
        rewardRate = IBaseRewardPool(_rewarder).rewardRate();
        totalSupply = IBaseRewardPool(_rewarder).totalSupply();
        periodFinish = IBaseRewardPool(_rewarder).periodFinish();
    }

    function _computeTotalAPR() internal returns (uint256 apr) {
        // Get reward pool metrics for the main rewarder and take a snapshot if necessary
        (uint256 rewardRate, uint256 totalSupply, uint256 periodFinish) = _getRewardPoolMetrics(address(rewarder));
        if (_shouldSnapshot(address(rewarder), rewardRate, periodFinish, totalSupply)) {
            _snapshot(address(rewarder), totalSupply, rewardRate);
        }

        // slither-disable-next-line reentrancy-no-eth
        uint256 lpPrice = _getPriceInEth(resolveLpToken());
        address rewardToken = address(rewarder.rewardToken());

        // Compute APR factors for the main rewarder if the period is still active

        apr += _computeAPR(address(rewarder), lpPrice, rewardToken, rewardRate, periodFinish);

        // Compute APR factors for the platform rewarder if the period is still active
        rewardRate = getPlatformTokenMintAmount(platformToken, rewardRate);
        apr += _computeAPR(address(rewarder), lpPrice, rewardToken, rewardRate, periodFinish);

        // Determine the number of extra rewarders and process each one
        uint256 extraRewardsLength = rewarder.extraRewardsLength();
        for (uint256 i = 0; i < extraRewardsLength; ++i) {
            address extraRewarder = rewarder.extraRewards(i);
            (rewardRate, totalSupply, periodFinish) = _getRewardPoolMetrics(extraRewarder);

            // Take a snapshot for the extra rewarder if necessary
            if (_shouldSnapshot(extraRewarder, rewardRate, periodFinish, totalSupply)) {
                _snapshot(extraRewarder, totalSupply, rewardRate);
            }
            rewardToken = resolveRewardToken(extraRewarder);

            if (rewardToken != address(0)) {
                // Accumulate APR data from each extra rewarder if the period is still active
                apr += _computeAPR(extraRewarder, lpPrice, rewardToken, rewardRate, periodFinish);
            }
        }
        return apr;
    }

    function _computeAPR(
        address _rewarder,
        uint256 lpPrice,
        address rewardToken,
        uint256 rewardRate,
        uint256 periodFinish
    ) internal view returns (uint256 apr) {
        // slither-disable-start incorrect-equality
        // slither-disable-next-line timestamp
        if (block.timestamp > periodFinish || rewardRate == 0) return 0;
        // slither-disable-end incorrect-equality

        uint256 price = _getIncentivePrice(rewardToken);

        uint256 numerator = rewardRate * Stats.SECONDS_IN_YEAR * price * 1e18;
        uint256 denominator = safeTotalSupplies[_rewarder] * lpPrice;

        return denominator == 0 ? 0 : numerator / denominator;
    }

    /// @notice returns the platform tokens earned given the amount of main rewarder tokens
    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view virtual returns (uint256);

    /// @notice returns the address of the stash token for Convex & Aura
    function resolveRewardToken(address extraRewarder) public view virtual returns (address rewardToken);

    // @notice returns the address of the lp token that is staked into the rewards platform
    function resolveLpToken() public view virtual returns (address lpToken);
}
