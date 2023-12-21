// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity >=0.8.7;

import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { AuraCalculator } from "src/stats/calculators/AuraCalculator.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { IOffchainAggregator } from "src/interfaces/external/chainlink/IOffchainAggregator.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { StatsSystemIntegrationTestBase } from "test/stats/calculators/base/StatsSystemIntegrationTestBase.t.sol";
import {
    AURA_MAINNET,
    AURA_BOOSTER,
    BAL_CL_FEED_MAINNET,
    BAL_MAINNET,
    RETH_CL_FEED_MAINNET,
    RETH_MAINNET
} from "test/utils/Addresses.sol";

contract AuraCalculatorIntegrationTest is StatsSystemIntegrationTestBase {
    AuraCalculator internal _calculator;
    IDexLSTStats internal _balancerStats;
    address internal _auraFeed;
    address auraRewarder;
    address balancerPool;

    event IncentiveSnapshot(
        uint256 totalApr,
        uint256 incentiveCredits,
        uint256 lastIncentiveTimestamp,
        bool decayState,
        uint256 decayInitTimestamp
    );

    function setUp() public {
        super.setUp(18_817_911);

        // Setup rETH Oracle
        _chainlinkOracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        _rootPriceOracle.registerMapping(RETH_MAINNET, _chainlinkOracle);

        // Setup BAL Oracle
        _chainlinkOracle.registerChainlinkOracle(
            BAL_MAINNET, IAggregatorV3Interface(BAL_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        _rootPriceOracle.registerMapping(BAL_MAINNET, _chainlinkOracle);
        _incentivePricing.setRegisteredToken(BAL_MAINNET);

        // Aura doesn't have an oracle at this time, just mocking it
        _auraFeed = vm.addr(3434);
        address auraAggregator = vm.addr(34_341);
        vm.label(_auraFeed, "auraChainlinkFeed");
        vm.label(auraAggregator, "auraChainlinkAggregator");
        vm.mockCall(
            _auraFeed,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(23_489, 230_948_230_948, block.timestamp, block.timestamp, 234)
        );
        vm.mockCall(_auraFeed, abi.encodeWithSelector(IAggregatorV3Interface.decimals.selector), abi.encode(18));
        vm.mockCall(
            _auraFeed, abi.encodeWithSelector(IAggregatorV3Interface.aggregator.selector), abi.encode(auraAggregator)
        );
        vm.mockCall(auraAggregator, abi.encodeWithSelector(IOffchainAggregator.minAnswer.selector), abi.encode(0));
        vm.mockCall(auraAggregator, abi.encodeWithSelector(IOffchainAggregator.maxAnswer.selector), abi.encode(10e18));
        _chainlinkOracle.registerChainlinkOracle(
            AURA_MAINNET, IAggregatorV3Interface(_auraFeed), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        _rootPriceOracle.registerMapping(AURA_MAINNET, _chainlinkOracle);
        _incentivePricing.setRegisteredToken(AURA_MAINNET);

        // Aura + Balancer rETH/WETH
        // Reward tokens are LDO and wstETH atm
        auraRewarder = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;
        balancerPool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

        _rootPriceOracle.registerMapping(balancerPool, _balancerMetaOracle);

        // Using fake base Balancer stats
        _balancerStats = IDexLSTStats(vm.addr(1012));
        vm.label(address(_balancerStats), "balancerStats");

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

        vm.mockCall(address(_balancerStats), abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(data));

        bytes32[] memory dependantAprs = new bytes32[](0);
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: auraRewarder,
            underlyerStats: address(_balancerStats),
            platformToken: AURA_MAINNET
        });
        bytes memory encodedInitData = abi.encode(initData);

        _calculator = new AuraCalculator(_systemRegistry, AURA_BOOSTER);
        vm.makePersistent(address(_calculator));
        _calculator.initialize(dependantAprs, encodedInitData);
    }

    function test_SetUp() public {
        assertEq(address(_calculator) != address(0), true);
        assertEq(address(_balancerStats) != address(0), true);
    }

    function test_CanPerformInitialSnapshot() public {
        vm.expectEmit(true, true, true, false);
        emit IncentiveSnapshot(0, 0, 0, false, 0);
        _calculator.snapshot();
    }

    function test_CanPerformFollowupSnapshot() public {
        vm.expectEmit(true, true, true, false);
        emit IncentiveSnapshot(0, 0, 0, false, 0);
        _calculator.snapshot();

        // Roughly 1 day and 9 hours past the previous snapshot
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_827_889);

        // Update our mock pricing timestamps
        vm.mockCall(
            _auraFeed,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(23_489, 230_948_230_948, block.timestamp, block.timestamp, 234)
        );

        address[] memory tokensToSnapshot = new address[](2);
        tokensToSnapshot[0] = AURA_MAINNET;
        tokensToSnapshot[1] = BAL_MAINNET;

        _incentivePricing.snapshot(tokensToSnapshot);

        vm.expectEmit(true, true, true, false);
        emit IncentiveSnapshot(0, 0, 0, false, 0);
        _calculator.snapshot();
    }

    function test_ResolveLpTokenIsActualPoolToken() public {
        address resolvedToken = _calculator.resolveLpToken();

        assertEq(resolvedToken, balancerPool, "balancerPool");
        assertFalse(resolvedToken == IBaseRewardPool(auraRewarder).stakingToken(), "stakingToken");
    }
}
