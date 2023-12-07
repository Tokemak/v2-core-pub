// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Stats } from "src/stats/Stats.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { IProtocolFeesCollector } from "src/interfaces/external/balancer/IProtocolFeesCollector.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Balancer Stable Pool Calculator Base
/// @notice Generates stats for Balancer Stable pools
abstract contract BalancerStablePoolCalculatorBase is IDexLSTStats, BaseStatsCalculator, Initializable {
    /// @notice The configured vault address
    IVault public immutable balancerVault;

    /// @notice The stats contracts for the underlying LSTs
    /// @return the LST stats contract for the specified index
    ILSTStats[] public lstStats;

    /// @notice The addresses of the pools reserve tokens
    /// @return the reserve token address for the specified index
    address[] public reserveTokens;

    /// @notice The number of underlying tokens in the pool
    uint256 public numTokens;

    /// @notice The Balancer pool address that the stats are for
    address public poolAddress;

    /// @notice The Balancer pool id that the stats are for
    bytes32 public poolId;

    /// @notice The most recent filtered feeApr. Typically retrieved via the current method
    uint256 public feeApr;

    /// @notice Flag indicating if the feeApr filter is initialized
    bool public feeAprFilterInitialized;

    /// @notice The last time a snapshot was taken
    uint256 public lastSnapshotTimestamp;

    /// @notice The pool's virtual price the last time a snapshot was taken
    uint256 public lastVirtualPrice;

    /// @notice The ethPerShare for the reserve tokens
    uint256[] public lastEthPerShare;

    bytes32 private _aprId;

    struct InitData {
        address poolAddress;
    }

    error InvalidPool(address poolAddress);
    error InvalidPoolId(address poolAddress);
    error DependentAprIdsMismatchTokens(uint256 numDependentAprIds, uint256 numCoins);

    constructor(ISystemRegistry _systemRegistry, address _balancerVault) BaseStatsCalculator(_systemRegistry) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");
        balancerVault = IVault(_balancerVault);
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return poolAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.poolAddress, "poolAddress");
        poolAddress = decodedInitData.poolAddress;

        poolId = IBalancerPool(poolAddress).getPoolId();
        if (poolId == bytes32(0)) revert InvalidPoolId(poolAddress);

        // reserveTokens addresses are checked against the dependentAprIds in a later step
        (IERC20[] memory _reserveTokens,) = getPoolTokens();

        numTokens = _reserveTokens.length;
        if (numTokens == 0) {
            revert InvalidPool(poolAddress);
        }

        // We should have the same number of calculators sent in as there are coins
        if (dependentAprIds.length != numTokens) {
            revert DependentAprIdsMismatchTokens(dependentAprIds.length, numTokens);
        }

        _aprId = Stats.generateBalancerPoolIdentifier(poolAddress);

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();
        lstStats = new ILSTStats[](numTokens);
        reserveTokens = new address[](numTokens);
        lastEthPerShare = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = address(_reserveTokens[i]);
            Errors.verifyNotZero(coin, "coin");

            reserveTokens[i] = coin;

            // call now to revert at init if there is an issue b/c this call is made in other calculations
            // slither-disable-next-line unused-return
            IERC20Metadata(coin).decimals();

            if (dependentAprId != Stats.NOOP_APR_ID) {
                IStatsCalculator calculator = registry.getCalculator(dependentAprId);

                // Ensure that the calculator we configured is meant to handle the token
                // setup on the pool. Individual token calculators use the address of the token
                // itself as the address id
                if (calculator.getAddressId() != coin) {
                    revert Stats.CalculatorAssetMismatch(dependentAprId, address(calculator), coin);
                }

                ILSTStats stats = ILSTStats(address(calculator));
                lstStats[i] = stats;

                lastEthPerShare[i] = stats.calculateEthPerToken();
            }
        }

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = getVirtualPrice();
        feeAprFilterInitialized = false;
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view override returns (bool) {
        if (feeAprFilterInitialized) {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        } else {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        }
    }

    /// @inheritdoc IDexLSTStats
    function current() external returns (DexLSTStatsData memory) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256[] memory reservesInEth = new uint256[](numTokens);
        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](numTokens);

        (, uint256[] memory balances) = getPoolTokens();

        for (uint256 i = 0; i < numTokens; i++) {
            reservesInEth[i] = calculateReserveInEthByIndex(pricer, balances, i);
            ILSTStats stats = lstStats[i];
            if (address(stats) != address(0)) {
                ILSTStats.LSTStatsData memory statsData = stats.current();

                statsData.baseApr = adjustForBalancerAdminFee(statsData.baseApr);
                lstStatsData[i] = statsData;
            }
        }

        // we want to return zero values
        // slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            feeApr: feeApr,
            reservesInEth: reservesInEth,
            lstStatsData: lstStatsData,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }

    /// @notice Capture stat data about this setup
    /// @dev This is protected by the STATS_SNAPSHOT_ROLE
    function _snapshot() internal override {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256 currentVirtualPrice = getVirtualPrice();
        (, uint256[] memory balances) = getPoolTokens();

        uint256[] memory currentEthPerShare = new uint256[](numTokens);
        uint256[] memory reservesInEth = new uint256[](numTokens);

        // subtracting base yield is an approximation b/c it uses the point-in-time reserve balances to estimate the
        // yield earned from the rebasing token. An attacker could shift the balance of the pool, causing us to believe
        // the fee apr is higher or lower. For a number of reasons, FeeApr has a low weight in the rebalancing logic.
        // LMP strategies understand that this signal can be noisy and correct accordingly A price check against an
        // oracle is an option to further mitigate the issue
        uint256 weightedBaseApr = 0;
        uint256 totalReservesInEth = 0;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 reserveValue = calculateReserveInEthByIndex(pricer, balances, i);
            reservesInEth[i] = reserveValue;
            totalReservesInEth += reserveValue;

            ILSTStats stats = lstStats[i];
            if (address(stats) != address(0)) {
                uint256 underlyingEthPerShare = stats.calculateEthPerToken();
                currentEthPerShare[i] = underlyingEthPerShare;
                weightedBaseApr += Stats.calculateAnnualizedChangeMinZero(
                    lastSnapshotTimestamp, lastEthPerShare[i], block.timestamp, underlyingEthPerShare
                ) * reserveValue;
            }
        }

        uint256 currentBaseApr = 0;
        if (totalReservesInEth > 0) {
            currentBaseApr = adjustForBalancerAdminFee(weightedBaseApr / totalReservesInEth);
        }

        uint256 currentFeeApr = Stats.calculateAnnualizedChangeMinZero(
            lastSnapshotTimestamp, lastVirtualPrice, block.timestamp, currentVirtualPrice
        );

        // slither-disable-next-line timestamp
        if (currentFeeApr > currentBaseApr) {
            currentFeeApr -= currentBaseApr;
        } else {
            currentFeeApr = 0;
        }

        uint256 newFeeApr;
        if (feeAprFilterInitialized) {
            // filter normally once the filter has been initialized
            newFeeApr = Stats.getFilteredValue(Stats.DEX_FEE_ALPHA, feeApr, currentFeeApr);
        } else {
            // first raw sample is used to initialize the filter
            newFeeApr = currentFeeApr;
            feeAprFilterInitialized = true;
        }

        // pricer handles reentrancy issues
        // slither-disable-next-line reentrancy-events
        emit DexSnapshotTaken(block.timestamp, feeApr, newFeeApr, currentFeeApr);

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = currentVirtualPrice;
        lastEthPerShare = currentEthPerShare;
        feeApr = newFeeApr;
    }

    function calculateReserveInEthByIndex(
        IRootPriceOracle pricer,
        uint256[] memory balances,
        uint256 index
    ) internal returns (uint256) {
        address token = reserveTokens[index];

        // the price oracle is always 18 decimals, so divide by the decimals of the token
        // to ensure that we always report the value in ETH as 18 decimals
        uint256 divisor = 10 ** IERC20Metadata(token).decimals();

        // the pricer handles the reentrancy issues
        // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
        return pricer.getPriceInEth(token) * balances[index] / divisor;
    }

    function adjustForBalancerAdminFee(uint256 value) internal view returns (uint256) {
        // balancer admin fee is 18 decimals
        // we want tot return a value that is the non-balancer amount
        uint256 adminFeeRate = 1e18 - balancerVault.getProtocolFeesCollector().getSwapFeePercentage();
        return value * adminFeeRate / 1e18;
    }

    function getVirtualPrice() internal view virtual returns (uint256 virtualPrice);

    /// @notice for composable pools the pool token is filtered out
    function getPoolTokens() internal view virtual returns (IERC20[] memory tokens, uint256[] memory balances);
}
