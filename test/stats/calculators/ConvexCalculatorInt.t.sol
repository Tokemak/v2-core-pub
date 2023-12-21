// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity >=0.8.7;

import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { StatsSystemIntegrationTestBase } from "test/stats/calculators/base/StatsSystemIntegrationTestBase.t.sol";
import {
    LDO_MAINNET,
    CVX_MAINNET,
    WSTETH_MAINNET,
    CRV_MAINNET,
    STETH_MAINNET,
    CONVEX_BOOSTER,
    STETH_CL_FEED_MAINNET,
    CRV_CL_FEED_MAINNET,
    CVX_CL_FEED_MAINNET,
    LDO_CL_FEED_MAINNET
} from "test/utils/Addresses.sol";

contract ConvexCalculatorIntegrationTest is StatsSystemIntegrationTestBase {
    ConvexCalculator internal _calculator;
    IDexLSTStats internal _curveStats;
    address convexRewarder;
    address curveLpToken;

    event IncentiveSnapshot(
        uint256 totalApr,
        uint256 incentiveCredits,
        uint256 lastIncentiveTimestamp,
        bool decayState,
        uint256 decayInitTimestamp
    );

    function setUp() public {
        super.setUp(18_817_911);

        // Setup stETH Oracle
        _chainlinkOracle.registerChainlinkOracle(
            STETH_MAINNET,
            IAggregatorV3Interface(STETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        _rootPriceOracle.registerMapping(STETH_MAINNET, _chainlinkOracle);

        _chainlinkOracle
            // Setup CRV Oracle
            .registerChainlinkOracle(
            CRV_MAINNET, IAggregatorV3Interface(CRV_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        _rootPriceOracle.registerMapping(CRV_MAINNET, _chainlinkOracle);
        _incentivePricing.setRegisteredToken(CRV_MAINNET);

        // Setup CVX Oracle
        _chainlinkOracle.registerChainlinkOracle(
            CVX_MAINNET, IAggregatorV3Interface(CVX_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        _rootPriceOracle.registerMapping(CVX_MAINNET, _chainlinkOracle);
        _incentivePricing.setRegisteredToken(CVX_MAINNET);

        // Setup LDO Oracle
        _chainlinkOracle.registerChainlinkOracle(
            LDO_MAINNET, IAggregatorV3Interface(LDO_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        _rootPriceOracle.registerMapping(LDO_MAINNET, _chainlinkOracle);
        _incentivePricing.setRegisteredToken(LDO_MAINNET);

        // Setup wstETH Incentive Token
        // Oracle is setup in the base
        _incentivePricing.setRegisteredToken(WSTETH_MAINNET);

        // Convex + Curve stETH/ETH Original
        // Reward tokens are LDO and wstETH atm
        convexRewarder = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;
        address curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        curveLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;

        _curveV1Oracle.registerPool(curvePool, curveLpToken, true);
        _rootPriceOracle.registerMapping(curveLpToken, _curveV1Oracle);

        // Using fake base Curve stats
        _curveStats = IDexLSTStats(vm.addr(1012));
        vm.label(address(_curveStats), "curveStats");

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

        vm.mockCall(address(_curveStats), abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(data));

        bytes32[] memory dependantAprs = new bytes32[](0);
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: convexRewarder,
            underlyerStats: address(_curveStats),
            platformToken: CVX_MAINNET
        });
        bytes memory encodedInitData = abi.encode(initData);

        _calculator = new ConvexCalculator(_systemRegistry, CONVEX_BOOSTER);
        vm.makePersistent(address(_calculator));
        _calculator.initialize(dependantAprs, encodedInitData);
    }

    function test_SetUp() public {
        assertEq(address(_calculator) != address(0), true);
        assertEq(address(_curveStats) != address(0), true);
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

        address[] memory tokensToSnapshot = new address[](3);
        tokensToSnapshot[0] = CRV_MAINNET;
        tokensToSnapshot[1] = CVX_MAINNET;
        tokensToSnapshot[2] = WSTETH_MAINNET;

        _incentivePricing.snapshot(tokensToSnapshot);

        vm.expectEmit(true, true, true, false);
        emit IncentiveSnapshot(0, 0, 0, false, 0);
        _calculator.snapshot();
    }

    function test_ResolveLpTokenIsActualPoolToken() public {
        address resolvedToken = _calculator.resolveLpToken();

        assertEq(resolvedToken, curveLpToken, "curveLpToken");
        assertFalse(resolvedToken == IBaseRewardPool(convexRewarder).stakingToken(), "stakingToken");
    }
}
