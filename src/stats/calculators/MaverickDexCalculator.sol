// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { IPoolPositionSlim } from "src/interfaces/external/maverick/IPoolPositionSlim.sol";
import { Stats } from "src/stats/Stats.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IMaverickFeeAprOracle } from "src/interfaces/oracles/IMaverickFeeAprOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MaverickDexCalculator is IDexLSTStats, BaseStatsCalculator, Initializable {
    uint256 public lastSnapshotTimestamp;

    ILSTStats[2] public lstStats;
    uint256 public dexReserveAlpha;

    IPool public pool;
    IPoolPositionSlim public boostedPosition;
    IMaverickFeeAprOracle public feeAprOracle;

    address[2] public reserveTokens;
    uint256[2] public reserveTokensDecimals;
    uint256[2] public reservesInEth;
    bytes32 private _aprId;

    bool public reservesInEthFilterInitialized;
    bool public feeAprFilterInitialized;

    uint256 public feeApr;

    struct InitData {
        address pool;
        address boostedPosition;
        uint256 dexReserveAlpha;
        address feeAprOracle;
    }

    error DependentAprIdsNot2();
    error BoostedPositionPoolDoesNotMatchInitPool();

    constructor(ISystemRegistry _systemRegistry) BaseStatsCalculator(_systemRegistry) {
        _disableInitializers();
    }

    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.pool, "pool");
        Errors.verifyNotZero(decodedInitData.boostedPosition, "boostedPosition");
        Errors.verifyNotZero(decodedInitData.dexReserveAlpha, "dexReserveAlpha");
        Errors.verifyNotZero(decodedInitData.feeAprOracle, "feeAprOracle");

        if (decodedInitData.pool != address(IPoolPositionSlim(decodedInitData.boostedPosition).pool())) {
            revert BoostedPositionPoolDoesNotMatchInitPool();
        }

        pool = IPool(decodedInitData.pool);
        boostedPosition = IPoolPositionSlim(decodedInitData.boostedPosition);
        feeAprOracle = IMaverickFeeAprOracle(decodedInitData.feeAprOracle);
        dexReserveAlpha = decodedInitData.dexReserveAlpha;

        address tokenA = address(pool.tokenA());
        address tokenB = address(pool.tokenB());
        reserveTokens[0] = tokenA;
        reserveTokens[1] = tokenB;

        reserveTokensDecimals[0] = IERC20Metadata(tokenA).decimals();
        reserveTokensDecimals[1] = IERC20Metadata(tokenB).decimals();

        _aprId = keccak256(abi.encode("maverick", pool, boostedPosition));

        if (dependentAprIds.length != 2) {
            revert DependentAprIdsNot2();
        }

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();

        for (uint256 i = 0; i < 2; ++i) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = reserveTokens[i];
            Errors.verifyNotZero(coin, "coin");

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
            }
        }
    }

    function shouldSnapshot() public view virtual override returns (bool takeSnapshot) {
        // snapshot both dex reserves and fee apr at the same time.
        // slither-disable-next-line timestamp
        takeSnapshot = (block.timestamp - lastSnapshotTimestamp) > Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
    }

    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    function getAddressId() external view returns (address) {
        return address(boostedPosition);
    }

    function _scaleDecimalsToOriginal(uint256 decimals, uint256 amount) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        } else if (decimals < 18) {
            uint256 exponent = 18 - decimals;
            amount = amount / (10 ** exponent);
        } else {
            uint256 exponent = decimals - 18;
            amount = amount * (10 ** exponent);
        }

        return amount;
    }

    function _snapshot() internal override {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        (uint256 reservesA, uint256 reservesB) = IPoolPositionSlim(boostedPosition).getReserves();

        //getReserves scales to 18, so we need to scale back to token decimals
        (reservesA, reservesB) = (
            _scaleDecimalsToOriginal(reserveTokensDecimals[0], reservesA),
            _scaleDecimalsToOriginal(reserveTokensDecimals[1], reservesB)
        );

        uint256[] memory balances = new uint256[](2);
        balances[0] = reservesA;
        balances[1] = reservesB;

        // slither-disable-next-line similar-names
        uint256 reservesAEthValue = calculateReserveInEthByIndex(pricer, balances, 0);
        uint256 reservesBEthValue = calculateReserveInEthByIndex(pricer, balances, 1);

        if (reservesInEthFilterInitialized) {
            // filter normally once the filter has been initialized
            reservesInEth[0] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[0], reservesAEthValue);
            reservesInEth[1] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[1], reservesBEthValue);
        } else {
            // first raw sample is used to initialize the filter
            reservesInEth[0] = reservesAEthValue;
            reservesInEth[1] = reservesBEthValue;
            reservesInEthFilterInitialized = true;
        }

        uint256 currentFeeApr = feeAprOracle.getFeeApr(address(boostedPosition));

        if (feeAprFilterInitialized) {
            // filter normally once the filter has been initialized
            feeApr = Stats.getFilteredValue(Stats.DEX_FEE_ALPHA, feeApr, currentFeeApr);
        } else {
            // first raw sample is used to initialize the filter
            feeApr = currentFeeApr;
            feeAprFilterInitialized = true;
        }
        lastSnapshotTimestamp = block.timestamp;
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

        // We are using the balances directly here which can be manipulated but these values are
        // only used in the strategy where we do additional checks to ensure the pool
        // is a good state
        // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
        return pricer.getPriceInEth(token) * balances[index] / divisor;
    }

    function current() external returns (DexLSTStatsData memory) {
        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](2);
        // address(0) is for WETH
        if (address(lstStats[0]) != address(0)) {
            lstStatsData[0] = lstStats[0].current();
        }
        if (address(lstStats[1]) != address(0)) {
            lstStatsData[1] = lstStats[1].current();
        }

        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        (uint256 reservesA, uint256 reservesB) = IPoolPositionSlim(boostedPosition).getReserves();

        //getReserves scales to 18, so we need to scale back to token decimals
        (reservesA, reservesB) = (
            _scaleDecimalsToOriginal(reserveTokensDecimals[0], reservesA),
            _scaleDecimalsToOriginal(reserveTokensDecimals[1], reservesB)
        );

        uint256[] memory balances = new uint256[](2);
        balances[0] = reservesA;
        balances[1] = reservesB;

        // slither-disable-next-line similar-names
        uint256 reservesAEthValue = calculateReserveInEthByIndex(pricer, balances, 0);
        uint256 reservesBEthValue = calculateReserveInEthByIndex(pricer, balances, 1);

        uint256[] memory reservesInEthMemory = new uint256[](2);

        reservesInEthMemory[0] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[0], reservesAEthValue);
        reservesInEthMemory[1] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[1], reservesBEthValue);

        //slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            feeApr: feeApr,
            lstStatsData: lstStatsData,
            reservesInEth: reservesInEthMemory,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }
}
