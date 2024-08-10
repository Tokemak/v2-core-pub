// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count,state-visibility,max-line-length

import { Test } from "forge-std/Test.sol";
import { AutopoolETHStrategy, ISystemRegistry } from "src/strategy/AutopoolETHStrategy.sol";
import { AutopoolETHStrategyConfig } from "src/strategy/AutopoolETHStrategyConfig.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { TOKE_MAINNET, WETH_MAINNET, LDO_MAINNET } from "test/utils/Addresses.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { AutopoolETHStrategyTestHelpers as helpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";
import { Errors } from "src/utils/Errors.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { AutopoolDebt } from "src/vault/libs/AutopoolDebt.sol";
import { NavTracking } from "src/strategy/NavTracking.sol";
import { ViolationTracking } from "src/strategy/ViolationTracking.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Incentives } from "src/strategy/libs/Incentives.sol";
import { PriceReturn } from "src/strategy/libs/PriceReturn.sol";
import { SummaryStats } from "src/strategy/libs/SummaryStats.sol";
import { IAutopoolStrategy } from "src/interfaces/strategy/IAutopoolStrategy.sol";
import { ISummaryStatsHook } from "src/interfaces/strategy/ISummaryStatsHook.sol";

contract AutopoolETHStrategyTest is Test {
    using NavTracking for NavTracking.State;

    address private mockAutopoolETH = vm.addr(900);
    address private mockBaseAsset = vm.addr(600);
    address private mockInToken = vm.addr(701);
    address private mockOutToken = vm.addr(702);
    address private immutable mockInLSTToken = vm.addr(703);
    address private immutable mockOutLSTToken = vm.addr(704);
    address private mockInDest = vm.addr(801);
    address private mockOutDest = vm.addr(802);
    address private mockInStats = vm.addr(501);
    address private mockOutStats = vm.addr(502);

    IIncentivesPricingStats private incentivePricing = IIncentivesPricingStats(vm.addr(2));

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    RootPriceOracle private rootPriceOracle;

    AutopoolETHStrategyHarness private defaultStrat;
    IStrategy.RebalanceParams private defaultParams;
    IStrategy.SummaryStats private destOut;

    uint256 startBlockTime = 1000 days;

    event LstPriceGapSet(uint256 newPriceGap);
    event DustPositionPortionSet(uint256 newValue);
    event IdleThresholdsSet(uint256 newLowValue, uint256 newHighValue);

    function setUp() public {
        vm.warp(startBlockTime);

        vm.label(mockAutopoolETH, "autoPool");
        vm.label(mockBaseAsset, "baseAsset");
        vm.label(mockInDest, "inDest");
        vm.label(mockInToken, "inToken");
        vm.label(mockOutDest, "outDest");
        vm.label(mockOutToken, "outToken");

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        setAutopoolDefaultMocks();

        defaultStrat = deployStrategy(helpers.getDefaultConfig());
        // Set Idle thresholds
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));
        defaultStrat.setIdleThresholds(3e16, 7e16);
        // Revoke since we will test access in other tests
        accessController.revokeRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultParams = getDefaultRebalanceParams();

        setInDestDefaultMocks();
        setOutDestDefaultMocks();
        setTokenDefaultMocks();
        setIncentivePricing();
    }

    /* **************************************** */
    /* constructor Tests                        */
    /* **************************************** */

    function test_constructor_RevertIf_invalidConfig() public {
        // this test only tests a single failure to ensure that config validation is occurring
        // in the constructor. All other config validation tests are in AutopoolETHStrategyConfig tests
        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        // set init < min to trigger a failure
        cfg.swapCostOffset.initInDays = 10;
        cfg.swapCostOffset.minInDays = 11;
        vm.expectRevert(
            abi.encodeWithSelector(AutopoolETHStrategyConfig.InvalidConfig.selector, "swapCostOffset_initInDays")
        );
        defaultStrat = deployStrategy(cfg);
    }

    function test_constructor_RevertIf_InvalidHookOrder() public {
        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        address hook1 = makeAddr("HOOK1");
        address hook3 = makeAddr("HOOK3");

        cfg.hooks[1] = hook1;
        cfg.hooks[3] = hook3;

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategyConfig.InvalidConfig.selector, "hooks"));
        deployStrategy(cfg);
    }

    function test_constructor_SetsHooks() public {
        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        address hook1 = makeAddr("HOOK1");
        address hook2 = makeAddr("HOOK2");
        address hook3 = makeAddr("HOOK3");
        address hook4 = makeAddr("HOOK4");
        address hook5 = makeAddr("HOOK5");

        cfg.hooks[0] = hook1;
        cfg.hooks[1] = hook2;
        cfg.hooks[2] = hook3;
        cfg.hooks[3] = hook4;
        cfg.hooks[4] = hook5;

        AutopoolETHStrategyHarness localStrat = deployStrategy(cfg);

        assertEq(localStrat.getHooks()[0], hook1);
        assertEq(localStrat.getHooks()[1], hook2);
        assertEq(localStrat.getHooks()[2], hook3);
        assertEq(localStrat.getHooks()[3], hook4);
        assertEq(localStrat.getHooks()[4], hook5);
    }

    function test_constructor_SetsSomeHooks() public {
        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        address hook1 = makeAddr("HOOK1");
        address hook2 = makeAddr("HOOK2");
        address hook3 = makeAddr("HOOK3");

        cfg.hooks[0] = hook1;
        cfg.hooks[1] = hook2;
        cfg.hooks[2] = hook3;

        AutopoolETHStrategyHarness localStrat = deployStrategy(cfg);

        assertEq(localStrat.getHooks()[0], hook1);
        assertEq(localStrat.getHooks()[1], hook2);
        assertEq(localStrat.getHooks()[2], hook3);
        assertEq(localStrat.getHooks()[3], address(0));
        assertEq(localStrat.getHooks()[4], address(0));
    }

    /* **************************************** */
    /* initialize Tests                         */
    /* **************************************** */

    function test_initialize_RevertIf_systemRegistryMismatch() public {
        setAutopoolSystemRegistry(address(1));
        AutopoolETHStrategyHarness stratHarness =
            new AutopoolETHStrategyHarness(ISystemRegistry(address(systemRegistry)), helpers.getDefaultConfig());
        AutopoolETHStrategyHarness s = AutopoolETHStrategyHarness(Clones.clone(address(stratHarness)));

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.SystemRegistryMismatch.selector));
        s.initialize(mockAutopoolETH);
    }

    function test_initialize_RevertIf_autoPoolZero() public {
        AutopoolETHStrategyHarness harness =
            new AutopoolETHStrategyHarness(ISystemRegistry(address(systemRegistry)), helpers.getDefaultConfig());

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_autoPool"));
        harness.init(address(0));
    }

    /* **************************************** */
    /* getHooks Tests                           */
    /* **************************************** */

    function test_getHooks_ReturnsZeroAddresses_NoHooksSet() public {
        address[] memory hooks = defaultStrat.getHooks();

        assertEq(hooks.length, 5);
        for (uint256 i = 0; i < hooks.length; ++i) {
            assertEq(hooks[i], address(0));
        }
    }

    function test_getHooks_ReturnsHooksWhenSet() public {
        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        address hook1 = makeAddr("HOOK1");
        address hook2 = makeAddr("HOOK2");
        address hook3 = makeAddr("HOOK3");
        address hook4 = makeAddr("HOOK4");
        address hook5 = makeAddr("HOOK5");

        cfg.hooks[0] = hook1;
        cfg.hooks[1] = hook2;
        cfg.hooks[2] = hook3;
        cfg.hooks[3] = hook4;
        cfg.hooks[4] = hook5;

        AutopoolETHStrategyHarness localStrat = deployStrategy(cfg);

        address[] memory hooks = localStrat.getHooks();

        assertEq(hooks[0], hook1);
        assertEq(hooks[1], hook2);
        assertEq(hooks[2], hook3);
        assertEq(hooks[3], hook4);
        assertEq(hooks[4], hook5);
    }

    /* **************************************** */
    /* verifyRebalance Tests                    */
    /* **************************************** */
    function test_verifyRebalance_success() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolDestinationBalanceOf(mockOutDest, 200e18);

        // 0.50% slippage
        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        // 4% composite return
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.095656855707106964e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);

        // 3% composite return
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0.03e18;
        setStatsCurrent(mockOutStats, outStats);

        // verify the swapCostOffset period
        // the compositeReturns have been configured specifically for a 28 day offset
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    /* **************************************** */
    /* verifyRebalance Tests                    */
    /* **************************************** */
    function test_verifyRebalance_IdleThresholds() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolTotalAssets(1000e18);
        setAutopoolIdle(400e18);
        defaultParams.destinationOut = mockAutopoolETH;
        defaultParams.tokenOut = mockBaseAsset;

        // 0.50% slippage
        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        // 4% composite return
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.095656855707106964e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);

        // 3% composite return
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0;
        setStatsCurrent(mockOutStats, outStats);

        // verify the swapCostOffset period
        // the compositeReturns have been configured specifically for a 28 day offset
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        bool success;
        (success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);

        // 0.25% slippage
        defaultParams.amountIn = 399e18;
        defaultParams.amountOut = 400e18;
        // Expect error in rebalance check since we are trying to draw down Idle below High threshold (7%)
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.IdleHighThresholdViolated.selector));
        (success,) = defaultStrat.verifyRebalance(defaultParams, destOut);

        // 0.29% slippage
        defaultParams.amountIn = 339e18;
        defaultParams.amountOut = 340e18;
        // Expect error in rebalance check since we are trying to draw down Idle below High threshold (7%)
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.IdleHighThresholdViolated.selector));
        (success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyLSTPriceGap_Revert() public {
        // this test verifies that revert logic is followed based on tolerance
        // of safe-spot price for LST
        vm.warp(10 hours);
        defaultStrat._setLastRebalanceTimestamp(1 hours);
        setTokenSpotPrice(mockOutLSTToken, 99e16); // set spot OutToken price slightly lower than safe
        setTokenSpotPrice(mockInLSTToken, 101e16); // set spot OutToken price slightly higher than safe
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.LSTPriceGapToleranceExceeded.selector));
        defaultStrat.getRebalanceOutSummaryStats(defaultParams);

        setTokenSpotPrice(mockOutLSTToken, 99.89e16); // set spot price slightly lower than safe near tolerance
        setTokenSpotPrice(mockInLSTToken, 100e16); // set spot = safe
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.LSTPriceGapToleranceExceeded.selector));
        defaultStrat.getRebalanceOutSummaryStats(defaultParams);
    }

    function test_getRebalanceOutSummaryStats_UsesDestinationSafePrice() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolDestinationBalanceOf(mockOutDest, 200e18);

        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.095656855707106963e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0.03e18;
        setStatsCurrent(mockOutStats, outStats);

        setDestinationSafePrice(mockOutDest, 1817e18);

        IStrategy.SummaryStats memory destOutSummary = defaultStrat.getRebalanceOutSummaryStats(defaultParams);
        assertEq(destOutSummary.pricePerShare, 1817e18);
    }

    function test_getRebalanceSummaryStats_ReturnsDataForDestination() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolDestinationBalanceOf(mockOutDest, 200e18);

        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.095656855707106963e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0.03e18;
        setStatsCurrent(mockOutStats, outStats);

        setDestinationSafePrice(mockOutDest, 1817e18);

        IStrategy.SummaryStats memory destOutSummary = defaultStrat.getDestinationSummaryStats(
            defaultParams.destinationIn, IAutopoolStrategy.RebalanceDirection.In, 1e18
        );
        assertGt(destOutSummary.pricePerShare, 0);
    }

    function test_getRebalanceSummaryStats_ReturnsDataForIdle() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        IStrategy.SummaryStats memory destOutSummary =
            defaultStrat.getDestinationSummaryStats(mockAutopoolETH, IAutopoolStrategy.RebalanceDirection.In, 1e18);
        assertEq(destOutSummary.pricePerShare, 1e18);
    }

    function test_getRebalanceOutSummaryStats_RevertIf_invalidParams() public {
        // this test ensures that `validateRebalanceParams` is called. It is not exhaustive
        defaultParams.amountIn = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amountIn"));
        defaultStrat.getRebalanceOutSummaryStats(defaultParams);
    }

    function test_verifyRebalance_RevertIf_invalidRebalanceToIdle() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from Autopool

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // set the in token to idle
        defaultParams.destinationIn = mockAutopoolETH;
        defaultParams.tokenIn = mockBaseAsset;

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_returnTrueOnValidRebalanceToIdleCleanUpDust() public {
        // make the strategy paused to ensure that rebalances to idle can still occur
        setDestinationIsShutdown(mockOutDest, false); // force trim
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from Autopool
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 90e17;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 99e17, // implied price of 1.1
            cachedMinDebtValue: 99e17, // implied price of 1.1
            cachedMaxDebtValue: 99e17, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 90e17 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 90e17;
        defaultParams.amountIn = 90e17;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 90e17, 99e17);

        // set the in token to idle
        defaultParams.destinationIn = mockAutopoolETH;
        defaultParams.tokenIn = mockBaseAsset;

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_returnTrueOnValidRebalanceToIdleIdleUp() public {
        // make the strategy paused to ensure that rebalances to idle can still occur
        setDestinationIsShutdown(mockOutDest, false); // force trim
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from Autopool
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 90e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 99e18, // implied price of 1.1
            cachedMinDebtValue: 99e18, // implied price of 1.1
            cachedMaxDebtValue: 99e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 90e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 40e18;
        defaultParams.amountIn = 40e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolIdle(15e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 90e18, 99e18);

        // set the in token to idle
        defaultParams.destinationIn = mockAutopoolETH;
        defaultParams.tokenIn = mockBaseAsset;

        // Successful rebalance to Idle
        bool success;
        // Expect success to be true since idle is currently 1.5% and low idle threshold is 3%, high is 7%
        (success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);

        // AmountOut results in excess Idle
        defaultParams.amountOut = 85e18;
        defaultParams.amountIn = 85e18;
        // Expect error in rebalance check since we are trying to 8.5% when high threshold is 7%
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InvalidRebalanceToIdle.selector));
        (success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_returnTrueOnValidRebalanceToIdle() public {
        // make the strategy paused to ensure that rebalances to idle can still occur
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(10 days);

        setDestinationIsShutdown(mockOutDest, true); // force trim
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from Autopool
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: 91 days, // unused
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // set the in token to idle
        defaultParams.destinationIn = mockAutopoolETH;
        defaultParams.tokenIn = mockBaseAsset;

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_RevertIf_paused() public {
        // pause config is for 90 days, so set block.timestamp - pauseTimestamp = 90 days
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.StrategyPaused.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_TooSoon() public {
        // rebalance gap is for 8 hours, so set block.timestamp - pauseTimestamp = 7 hours
        vm.warp(8 hours);
        defaultStrat._setLastRebalanceTimestamp(1 hours);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.RebalanceTimeGapNotMet.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_maxSlippageExceeded() public {
        // max slippage on a normal swap is 1%
        // token prices are set 1:1 with eth, so to get 1% slippage adjust the in/out values
        defaultParams.amountIn = 989e17; // 98.9
        defaultParams.amountOut = 100e18; // 100

        vm.warp(9 hours);
        defaultStrat._setLastRebalanceTimestamp(1 hours);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_maxDiscountOrPremiumExceeded() public {
        vm.warp(startBlockTime + 180 days);

        // setup for maxDiscount check
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = startBlockTime + 180 days;
        inStats.reservesInEth = new uint256[](1);
        inStats.reservesInEth[0] = 1e18;
        inStats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        ILSTStats.LSTStatsData memory lstStat;
        lstStat.lastSnapshotTimestamp = startBlockTime + 180 days;
        lstStat.discount = 0.021e18; // above 2% max discount
        inStats.lstStatsData[0] = lstStat;
        setStatsCurrent(mockInStats, inStats);

        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = startBlockTime + 180 days;
        setStatsCurrent(mockOutStats, outStats);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxDiscountExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        // setup for maxPremium check
        lstStat.discount = -0.011e18; // above 1% max premium
        setStatsCurrent(mockInStats, inStats);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxPremiumExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_swapCostTooHigh() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolDestinationBalanceOf(mockOutDest, 200e18);

        // 0.50% slippage
        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        // 4% composite return
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.095656855707106963e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);

        // 3% composite return
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0.03e18;
        setStatsCurrent(mockOutStats, outStats);

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);
        destOut = defaultStrat.getRebalanceOutSummaryStats(defaultParams);
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.SwapCostExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        // verify that it gets let through just above the required swapCost
        inStats.feeApr = 0.095656855707106964e18; // increment failing apr by 1
        setStatsCurrent(mockInStats, inStats);

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_RevertIf_swapCostTooHighSameToken() public {
        vm.warp(181 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setAutopoolDestinationBalanceOf(mockOutDest, 200e18);

        // 0.50% slippage
        defaultParams.amountIn = 199e18; // 199 eth
        defaultParams.amountOut = 200e18; // 200 eth

        // set the underlying to be the same between the two destinations
        defaultParams.tokenOut = defaultParams.tokenIn;
        setDestinationUnderlying(mockOutDest, mockInToken);

        // 4% composite return
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.feeApr = 0.161162957645369705e18; // calculated manually
        setStatsCurrent(mockInStats, inStats);

        // 3% composite return
        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        outStats.feeApr = 0.03e18;
        setStatsCurrent(mockOutStats, outStats);

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        destOut = defaultStrat.getRebalanceOutSummaryStats(defaultParams);
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.SwapCostExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        // verify that it gets let through just above the required swapCost
        inStats.feeApr = 0.161162957645369706e18; // increment by 1
        setStatsCurrent(mockInStats, inStats);

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    /* ****************************************** */
    /* updateWithdrawalQueueAfterRebalance Tests  */
    /* ****************************************** */

    // TODO: Move these to Vault

    // function test_updateWithdrawalQueueAfterRebalance_betweenDestinations() public {
    //     vm.prank(mockAutopoolETH);
    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueHead,
    // defaultParams.destinationOut),
    // 1
    //     );
    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueTail,
    // defaultParams.destinationIn), 1
    //     );

    //     defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    // }

    // function test_updateWithdrawalQueueAfterRebalance_fromIdle() public {
    //     defaultParams.destinationOut = address(mockAutopoolETH);

    //     vm.prank(mockAutopoolETH);

    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueHead,
    // defaultParams.destinationOut),
    // 0
    //     );
    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueTail,
    // defaultParams.destinationIn), 1
    //     );

    //     defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    // }

    // function test_updateWithdrawalQueueAfterRebalance_toIdle() public {
    //     defaultParams.destinationIn = address(mockAutopoolETH);

    //     vm.prank(mockAutopoolETH);

    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueHead,
    // defaultParams.destinationOut),
    // 1
    //     );
    //     vm.expectCall(
    //         address(mockAutopoolETH), abi.encodeCall(IAutopool.addToWithdrawalQueueTail,
    // defaultParams.destinationIn), 0
    //     );

    //     defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    // }

    /* **************************************** */
    /* validateRebalanceParams Tests            */
    /* **************************************** */
    function test_validateRebalanceParams_success() public view {
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_ZeroParams() public {
        // start with everything at zero
        IStrategy.RebalanceParams memory params;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "destinationIn"));
        defaultStrat._validateRebalanceParams(params);

        params.destinationIn = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "destinationOut"));
        defaultStrat._validateRebalanceParams(params);

        params.destinationOut = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenIn"));
        defaultStrat._validateRebalanceParams(params);

        params.tokenIn = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "tokenOut"));
        defaultStrat._validateRebalanceParams(params);

        params.tokenOut = vm.addr(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amountIn"));
        defaultStrat._validateRebalanceParams(params);

        params.amountIn = 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amountOut"));
        defaultStrat._validateRebalanceParams(params);
    }

    function test_validateRebalanceParams_RevertIf_destinationInNotRegistered() public {
        setAutopoolDestinationRegistered(defaultParams.destinationIn, false);
        vm.expectRevert(
            abi.encodeWithSelector(AutopoolETHStrategy.UnregisteredDestination.selector, defaultParams.destinationIn)
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destinationOutNotRegistered() public {
        setAutopoolDestinationRegistered(defaultParams.destinationOut, false);
        vm.expectRevert(
            abi.encodeWithSelector(AutopoolETHStrategy.UnregisteredDestination.selector, defaultParams.destinationOut)
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_handlesQueuedForRemoval() public {
        // set both destinations as only queued for removal
        setAutopoolDestinationRegistered(defaultParams.destinationOut, false);
        setAutopoolDestQueuedForRemoval(defaultParams.destinationOut, true);
        setAutopoolDestinationRegistered(defaultParams.destinationIn, false);
        setAutopoolDestQueuedForRemoval(defaultParams.destinationIn, true);

        // expect not to revert
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_handlesIdle() public {
        // set in == idle
        defaultParams.destinationIn = mockAutopoolETH;
        defaultParams.tokenIn = mockBaseAsset;

        // ensure that the autoPool is not registered
        setAutopoolDestinationRegistered(defaultParams.destinationIn, false);

        // expect this not to revert
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_autoPoolShutdownAndNotIdle() public {
        setAutopoolVaultIsShutdown(true);
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.OnlyRebalanceToIdleAvailable.selector));

        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destinationsMatch() public {
        setAutopoolDestinationRegistered(vm.addr(1), true);
        defaultParams.destinationIn = vm.addr(1);
        defaultParams.destinationOut = vm.addr(1);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.RebalanceDestinationsMatch.selector));
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destInIsVaultButTokenNotBase() public {
        // this means we're expecting the baseAsset as the return token
        defaultParams.destinationIn = mockAutopoolETH;

        vm.expectRevert(
            abi.encodeWithSelector(
                AutopoolETHStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                mockAutopoolETH,
                defaultParams.tokenIn,
                mockBaseAsset
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destInUnderlyingMismatch() public {
        defaultParams.tokenIn = vm.addr(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                AutopoolETHStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                defaultParams.destinationIn,
                mockInToken,
                defaultParams.tokenIn
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destInOutVaultButTokenNotBase() public {
        // this means we're expecting the baseAsset as the return token
        defaultParams.destinationOut = mockAutopoolETH;

        vm.expectRevert(
            abi.encodeWithSelector(
                AutopoolETHStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                mockAutopoolETH,
                defaultParams.tokenOut,
                mockBaseAsset
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutInsufficientIdle() public {
        defaultParams.destinationOut = mockAutopoolETH;
        defaultParams.tokenOut = mockBaseAsset;

        setAutopoolIdle(defaultParams.amountOut - 1);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InsufficientAssets.selector, mockBaseAsset));
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutUnderlyingMismatch() public {
        defaultParams.tokenOut = vm.addr(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                AutopoolETHStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                defaultParams.destinationOut,
                mockOutToken,
                defaultParams.tokenOut
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutInsufficient() public {
        setAutopoolDestinationBalanceOf(mockOutDest, defaultParams.amountOut - 1);
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InsufficientAssets.selector, mockOutToken));
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    /* **************************************** */
    /* getRebalanceValueStats Tests             */
    /* **************************************** */
    function test_getRebalanceValueStats_basic() public {
        setDestinationSpotPrice(mockOutDest, 100e16);
        setDestinationSpotPrice(mockInDest, 99e16); // set in price slightly lower than out

        defaultParams.amountOut = 78e18;
        defaultParams.amountIn = 77e18; // also set slightly lower than out token

        SummaryStats.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);

        assertEq(stats.outPrice, 100e16);
        assertEq(stats.inPrice, 99e16);

        uint256 expectedOutEthValue = 78e18;
        uint256 expectedInEthValue = 7623e16; // 77 * 0.99 = 76.23
        uint256 expectedSwapCost = 177e16; // 78 - 76.23 = 1.77
        uint256 expectedSlippage = 22_692_307_692_307_692; // 1.77 / 78 = 0.02269230769230769230769230769

        assertEq(stats.outEthValue, expectedOutEthValue);
        assertEq(stats.inEthValue, expectedInEthValue);
        assertEq(stats.swapCost, expectedSwapCost);
        assertEq(stats.slippage, expectedSlippage);
    }

    function test_getRebalanceValueStats_handlesDifferentDecimals() public {
        defaultParams.amountOut = 100e18; // 18 decimals
        defaultParams.amountIn = 100e12; // 12 decimals
        setTokenDecimals(mockInToken, 12);

        SummaryStats.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.inEthValue, 100e18);
        assertEq(stats.outEthValue, 100e18);
    }

    function test_getRebalanceValueStats_handlePositiveSlippage() public {
        // positive slippage should equal zero slippage
        defaultParams.amountOut = 100e18;
        defaultParams.amountIn = 101e18;

        SummaryStats.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.slippage, 0);
        assertEq(stats.swapCost, 0);
    }

    function test_getRebalanceValueStats_idleOutPricesAtOneToOne() public {
        // Setting all other possibilities to something that wouldn't be 1:1
        setDestinationSpotPrice(mockOutDest, 99e16);
        setDestinationSpotPrice(mockInDest, 99e16);
        setDestinationSpotPrice(mockAutopoolETH, 99e16);

        uint256 outAmount = 77.7e18;

        defaultParams.tokenOut = mockBaseAsset;
        defaultParams.destinationOut = mockAutopoolETH;
        defaultParams.amountOut = outAmount;

        SummaryStats.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.outPrice, 1e18, "outPrice");
        assertEq(stats.outEthValue, outAmount, "outEthValue");
    }

    /* **************************************** */
    /* verifyRebalanceToIdle Tests              */
    /* **************************************** */
    function test_verifyRebalanceToIdle_RevertIf_noActiveScenarioFound() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from Autopool

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 0);
    }

    function test_verifyRebalanceToIdle_trimOperation() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination not shutdown
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set trim to 10% of vault
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        dexStats.lstStatsData[0] = build10pctExitThresholdLst();
        setStatsCurrent(mockOutStats, dexStats);

        // set the destination to be 29% of the portfolio
        // rebalance will reduce to 24% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 2e16 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 2e16);

        defaultParams.amountOut = 250e18 - 60e18;
        defaultParams.amountIn = 50e18; // terrible exchange rate, but slippage isn't checked here
        setDestinationDebtValue(mockOutDest, 60e18, 66e18); // trim to 8.3%

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 0);
    }

    function test_verifyRebalanceToIdle_destinationShutdownSlippage() public {
        setDestinationIsShutdown(mockOutDest, true); // set destination to shutdown, 2.5% slippage
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15);
    }

    function test_verifyRebalanceToIdle_autoPoolShutdownSlippage() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination not shutdown
        setAutopoolVaultIsShutdown(true); // autoPool is shutdown, 1.5% slippage
        setAutopoolDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 15e15 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 15e15);
    }

    function test_verifyRebalanceToIdle_queuedForRemovalSlippage() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setAutopoolVaultIsShutdown(false); // ensure autoPool is not shutdown
        setAutopoolDestQueuedForRemoval(mockOutDest, true); // will return maxNormalOperationSlippage as max (1%)

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 1e16 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 1e16);
    }

    function test_verifyRebalanceToIdle_picksHighestSlippage() public {
        // set all conditions to true, ex trim for simplicity
        // destinationShutdown has the highest slippage at 2.5%
        setDestinationIsShutdown(mockOutDest, true);
        setAutopoolVaultIsShutdown(true);
        setAutopoolDestQueuedForRemoval(mockOutDest, true);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // excluding trim for simplicity
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15);
    }

    /* **************************************** */
    /* getDestinationTrimAmount Tests           */
    /* **************************************** */
    function test_getDestinationTrimAmount_handleEmpty() public {
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        uint256 trimAmount = defaultStrat._getDestinationTrimAmount(IDestinationVault(mockOutDest));
        assertEq(trimAmount, 1e18);
    }

    function test_getDestinationTrimAmount_noTrim() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](2);
        ILSTStats.LSTStatsData memory empty;
        dexStats.lstStatsData[0] = empty;
        dexStats.lstStatsData[1] = build10pctExitThresholdLst();
        dexStats.lstStatsData[1].discount = 3e16 - 1; // set just below the threshold so we shouldn't hit the trim

        setStatsCurrent(mockOutStats, dexStats);
        uint256 trimAmount = defaultStrat._getDestinationTrimAmount(IDestinationVault(mockOutDest));
        assertEq(trimAmount, 1e18);
    }

    function test_getDestinationTrimAmount_fullExit() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](3);
        dexStats.lstStatsData[0] = build10pctExitThresholdLst();
        dexStats.lstStatsData[1] = buildFullExitThresholdLst();

        setStatsCurrent(mockOutStats, dexStats);
        uint256 trimAmount = defaultStrat._getDestinationTrimAmount(IDestinationVault(mockOutDest));
        assertEq(trimAmount, 0);
    }

    function test_getDestinationTrimAmount_10pctExit() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](2);
        ILSTStats.LSTStatsData memory empty;
        dexStats.lstStatsData[0] = empty;
        dexStats.lstStatsData[1] = build10pctExitThresholdLst();

        setStatsCurrent(mockOutStats, dexStats);
        uint256 trimAmount = defaultStrat._getDestinationTrimAmount(IDestinationVault(mockOutDest));
        assertEq(trimAmount, 1e17);
    }

    function buildFullExitThresholdLst() private pure returns (ILSTStats.LSTStatsData memory) {
        ILSTStats.LSTStatsData memory lstStat;

        uint24[10] memory discountHistory;
        discountHistory[0] = 5e5;
        discountHistory[1] = 5e5;
        discountHistory[2] = 5e5;
        discountHistory[3] = 5e5;
        discountHistory[4] = 5e5;
        discountHistory[5] = 5e5;
        discountHistory[6] = 5e5;

        lstStat.discountHistory = discountHistory;
        lstStat.discount = 5e16; // exit threshold

        return lstStat;
    }

    function build10pctExitThresholdLst() private pure returns (ILSTStats.LSTStatsData memory) {
        ILSTStats.LSTStatsData memory lstStat;
        uint24[10] memory discountHistory;
        discountHistory[0] = 3e5;
        discountHistory[1] = 3e5;
        discountHistory[2] = 3e5;
        discountHistory[3] = 3e5;
        discountHistory[4] = 3e5;
        discountHistory[5] = 3e5;
        discountHistory[6] = 3e5;

        lstStat.discountHistory = discountHistory;
        lstStat.discount = 3e16; // below the full exit threshold, but at the discountThreshold

        return lstStat;
    }

    /* **************************************** */
    /* verifyTrimOperation Tests                */
    /* **************************************** */
    function test_verifyTrimOperation_handlesZeroTrimAmount() public {
        assertTrue(defaultStrat._verifyTrimOperation(defaultParams, 0));
    }

    function test_verifyTrimOperation_validRebalance() public {
        uint256 startingBalance = 250e18;
        AutopoolDebt.DestinationInfo memory info = AutopoolDebt.DestinationInfo({
            cachedDebtValue: 330e18, // implied price of 1.1
            cachedMinDebtValue: 330e18, // implied price of 1.1
            cachedMaxDebtValue: 330e18, // implied price of 1.1
            lastReport: startBlockTime,
            ownedShares: 300e18 // set higher than starting balance to handle withdraw scenario
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;

        setAutopoolTotalAssets(1000e18);
        setAutopoolDestInfo(mockOutDest, info);
        setAutopoolDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // autoPoolAssetsBeforeRebalance = 1000 (assets)
        // autoPoolAssetsAfterRebalance = 1000 (assets) + 50 (amountIn) + 220 (destValueAfter) - 275 (destValueBefore) =
        // 995
        // destination as % of total (before rebalance) = 275 / 1000 = 27.5%
        // destination as % of total (after rebalance) = 220 / 995 = 22.11%

        assertTrue(defaultStrat._verifyTrimOperation(defaultParams, 221_105_527_638_190_954));
        assertFalse(defaultStrat._verifyTrimOperation(defaultParams, 221_105_527_638_190_955));
    }

    /* **************************************** */
    /* getDiscountAboveThreshold Tests          */
    /* **************************************** */
    function test_getDiscountAboveThreshold() public {
        uint24[10] memory history;
        history[0] = 1e7; // 100%
        history[1] = 1e5; // 1%
        history[2] = 2e5; // 2%
        history[3] = 345e3; // 3.45%
        history[4] = 1e5; // 1%
        history[5] = 4444e2; // 4.444%
        history[6] = 1e6; // 10%
        history[7] = 123_456; // 1.23456%
        history[8] = 2e6; // 20%
        history[9] = 333e4; // 33.3%

        uint256 cnt1;
        uint256 cnt2;
        (cnt1, cnt2) = defaultStrat._getDiscountAboveThreshold(history, 1e7, 0);
        assertEq(cnt1, 1);
        assertEq(cnt2, 10);
        (cnt1, cnt2) = defaultStrat._getDiscountAboveThreshold(history, 0, 1e7);
        assertEq(cnt1, 10);
        assertEq(cnt2, 1);
        (cnt1, cnt2) = defaultStrat._getDiscountAboveThreshold(history, 0, 0);
        assertEq(cnt1, 10);
        assertEq(cnt2, 10);
        (cnt1, cnt2) = defaultStrat._getDiscountAboveThreshold(history, 1e6, 1e5);
        assertEq(cnt1, 4);
        assertEq(cnt2, 10);
        (cnt1, cnt2) = defaultStrat._getDiscountAboveThreshold(history, 1e7, 123_456);
        assertEq(cnt1, 1);
        assertEq(cnt2, 8);
    }

    /* **************************************** */
    /* getDestinationSummaryStats Tests         */
    /* **************************************** */
    function test_getDestinationSummaryStats_shouldHandleIdle() public {
        uint256 idle = 456e17;
        uint256 price = 3e17;
        setAutopoolIdle(idle);

        IStrategy.SummaryStats memory stats =
            defaultStrat._getDestinationSummaryStats(mockAutopoolETH, price, IAutopoolStrategy.RebalanceDirection.In, 1);

        // only these are populated when destination is idle asset
        assertEq(stats.destination, mockAutopoolETH);
        assertEq(stats.ownedShares, idle);
        assertEq(stats.pricePerShare, price);

        // rest should be zero
        assertEq(stats.baseApr, 0);
        assertEq(stats.feeApr, 0);
        assertEq(stats.incentiveApr, 0);
        assertEq(stats.priceReturn, 0);
        assertEq(stats.maxDiscount, 0);
        assertEq(stats.maxPremium, 0);
        assertEq(stats.compositeReturn, 0);
    }

    function test_getRebalanceInSummaryStats_PricesIdleWithSafePrice() public {
        uint256 idle = 456e17;
        setAutopoolIdle(idle);

        setTokenPrice(mockBaseAsset, 1.9e18);

        IStrategy.RebalanceParams memory rebalParams = IStrategy.RebalanceParams({
            destinationIn: mockAutopoolETH,
            amountIn: 1,
            tokenIn: mockBaseAsset,
            destinationOut: address(1),
            tokenOut: address(1),
            amountOut: 0
        });

        IStrategy.SummaryStats memory stats = defaultStrat._getRebalanceInSummaryStats(rebalParams);

        assertEq(stats.pricePerShare, 1.9e18);
    }

    function test_getDestinationSummaryStats_RevertIf_staleData() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days - 2 days - 1; // tolerance is 2 days
        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.StaleData.selector, "DexStats"));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, IAutopoolStrategy.RebalanceDirection.Out, 0);
    }

    function test_getDestinationSummaryStats_RevertIf_reserveStatsMismatch() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        stats.lstStatsData = new ILSTStats.LSTStatsData[](2);
        stats.reservesInEth = new uint256[](1);
        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(SummaryStats.LstStatsReservesMismatch.selector));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, IAutopoolStrategy.RebalanceDirection.Out, 0);
    }

    function test_getDestinationSummaryStats_RevertIf_staleLstData() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        stats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        stats.reservesInEth = new uint256[](1);
        stats.lstStatsData[0].lastSnapshotTimestamp = 180 days - 2 days - 1;

        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.StaleData.selector, "lstData"));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, IAutopoolStrategy.RebalanceDirection.Out, 0);
    }

    function test_getDestinationSummaryStats_calculatesWeightedResult() public {
        vm.warp(180 days);

        uint256 lpPrice = 12e17;
        uint256 rebalanceAmount = 62e18;

        // scenario
        // 2 LST Pool
        // 1x LST trading at a discount
        // 1x LST trading at a premium
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        stats.lstStatsData = new ILSTStats.LSTStatsData[](2);
        stats.reservesInEth = new uint256[](2);
        stats.feeApr = 0.01e18; // 1% fee apr

        // add incentives
        address rewardToken = vm.addr(123_456);
        setIncentivePrice(rewardToken, 1e18, 2e18);
        setTokenDecimals(rewardToken, 18);

        stats.stakingIncentiveStats.incentiveCredits = 1;
        stats.stakingIncentiveStats.safeTotalSupply = 110e18;
        stats.stakingIncentiveStats.rewardTokens = new address[](1);
        stats.stakingIncentiveStats.annualizedRewardAmounts = new uint256[](1);
        stats.stakingIncentiveStats.periodFinishForRewards = new uint40[](1);
        stats.stakingIncentiveStats.rewardTokens[0] = rewardToken;
        stats.stakingIncentiveStats.annualizedRewardAmounts[0] = 5e18;
        stats.stakingIncentiveStats.periodFinishForRewards[0] = 180 days;

        // LST #1
        stats.lstStatsData[0].lastSnapshotTimestamp = 180 days;
        stats.reservesInEth[0] = 12e18; // 12 eth
        stats.lstStatsData[0].discount = 0.01e18; // 1% discount
        stats.lstStatsData[0].baseApr = 0.04e18; // 4% staking yield

        // LST #2
        stats.lstStatsData[1].lastSnapshotTimestamp = 180 days;
        stats.reservesInEth[1] = 18e18; // 18 eth
        stats.lstStatsData[1].discount = -0.012e18; // 1.2% premium
        stats.lstStatsData[1].baseApr = 0.05e18; // 5% staking yield

        setStatsCurrent(mockOutStats, stats);
        setAutopoolDestinationBalanceOf(mockOutDest, 78e18);

        // test rebalance out
        IStrategy.SummaryStats memory summary = defaultStrat._getDestinationSummaryStats(
            mockOutDest, lpPrice, IAutopoolStrategy.RebalanceDirection.Out, rebalanceAmount
        );

        assertEq(summary.destination, mockOutDest);
        assertEq(summary.ownedShares, 78e18);
        assertEq(summary.pricePerShare, lpPrice);

        // ((4% * 12) + (5% * 18)) / (12 + 18) = 4.6%
        assertEq(summary.baseApr, 0.046e18);
        assertEq(summary.feeApr, 0.01e18);

        // totalSupplyInEth = (110 (starting safe supply) - 62 (amount being removed)) * 1.2 (price) = 57.6
        // expected apr = 5 (eth per year) / 57.6 = 8.68%
        assertEq(summary.incentiveApr, 37_878_787_878_787_878);

        // ((1% * 12 * 0.75) + (-1.2% * 18 * 1.0)) / (12 + 18) = -0.42%
        assertEq(summary.priceReturn, -0.0042e18);
        assertEq(summary.maxDiscount, 0.01e18);
        assertEq(summary.maxPremium, -0.012e18);
        // (4.6% * 1.0) + (1% * 1.0) + (8.68% * 0.9) + -0.42% = 12.992%
        assertApproxEqAbs(summary.compositeReturn, 85_890_909_090_909_090, 1e13 - 1);

        // test rebalance in
        summary = defaultStrat._getDestinationSummaryStats(
            mockOutDest, lpPrice, IAutopoolStrategy.RebalanceDirection.In, rebalanceAmount
        );

        assertEq(summary.destination, mockOutDest);
        assertEq(summary.ownedShares, 78e18);
        assertEq(summary.pricePerShare, lpPrice);
        // ((4% * 12) + (5% * 18)) / (12 + 18) = 4.6% => 46e15
        assertEq(summary.baseApr, 0.046e18);
        assertEq(summary.feeApr, 0.01e18);

        // rewards expire in less than 3 days, so no credit given
        assertEq(summary.incentiveApr, 0);
        // ((1% * 12 * 0.0) + (-1.2% * 18 * 1.0)) / (12 + 18) = -0.72% => -72e14
        assertEq(summary.priceReturn, -0.0072e18);
        assertEq(summary.maxDiscount, 1e16);
        assertEq(summary.maxPremium, -12e15);
        // (4.6% * 1.0) + (1% * 1.0) + (0% * 0.9) + -0.72% = 4.88% => 488e14
        assertEq(summary.compositeReturn, 488e14);
    }

    function test_getDestinationSummaryStats_DoesNotManipulate_NoHooksSet() public {
        uint256 submittedPrice = 1;

        vm.warp(180 days);

        // Set stats
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        setStatsCurrent(mockOutStats, stats);

        IStrategy.SummaryStats memory result = defaultStrat._getDestinationSummaryStats(
            mockOutDest, submittedPrice, IAutopoolStrategy.RebalanceDirection.Out, 1e18
        );

        // No hooks set, price should be exactly as submitted.
        assertEq(result.pricePerShare, submittedPrice);
    }

    function test_getDestinationSummaryStats_ManipulatesProperly_SomeHooksSet() public {
        uint256 submittedPrice = 1;

        vm.warp(180 days);

        // Set stats
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        setStatsCurrent(mockOutStats, stats);

        // Deploy three hooks
        address hook1 = address(new MockHook());
        address hook2 = address(new MockHook());
        address hook3 = address(new MockHook());

        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        // Set hooks in config
        cfg.hooks[0] = hook1;
        cfg.hooks[1] = hook2;
        cfg.hooks[2] = hook3;

        AutopoolETHStrategyHarness localStrat = deployStrategy(cfg);

        IStrategy.SummaryStats memory result = localStrat._getDestinationSummaryStats(
            mockOutDest, submittedPrice, IAutopoolStrategy.RebalanceDirection.Out, 1e18
        );

        // Checking for three incrementations
        assertEq(result.pricePerShare, submittedPrice + 3);
    }

    function test_getDestinationSummaryStats_ManipulatesProperly_AllHooksSet() public {
        uint256 submittedPrice = 1;

        vm.warp(180 days);

        // Set stats
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        setStatsCurrent(mockOutStats, stats);

        // Deploy hooks
        address hook1 = address(new MockHook());
        address hook2 = address(new MockHook());
        address hook3 = address(new MockHook());
        address hook4 = address(new MockHook());
        address hook5 = address(new MockHook());

        AutopoolETHStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        // Set hooks in config
        cfg.hooks[0] = hook1;
        cfg.hooks[1] = hook2;
        cfg.hooks[2] = hook3;
        cfg.hooks[3] = hook4;
        cfg.hooks[4] = hook5;

        AutopoolETHStrategyHarness localStrat = deployStrategy(cfg);

        IStrategy.SummaryStats memory result = localStrat._getDestinationSummaryStats(
            mockOutDest, submittedPrice, IAutopoolStrategy.RebalanceDirection.Out, 1e18
        );

        // Checking for five incrementations
        assertEq(result.pricePerShare, submittedPrice + 5);
    }

    /* **************************************** */
    /* calculateWeightedPriceReturn Tests       */
    /* **************************************** */
    function test_calculateWeightedPriceReturn_outDiscount() public {
        int256 priceReturn = 1e17; // 10%
        uint256 reserveValue = 34e18;
        IAutopoolStrategy.RebalanceDirection direction = IAutopoolStrategy.RebalanceDirection.Out;

        int256 actual = defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
        // 10% * 34 * 0.75 = 2.55 (1e36)
        int256 expected = 255e34;
        assertEq(actual, expected);
    }

    function test_calculateWeightedPriceReturn_inDiscount() public {
        int256 priceReturn = 1e17; // 10%
        uint256 reserveValue = 34e18;
        IAutopoolStrategy.RebalanceDirection direction = IAutopoolStrategy.RebalanceDirection.In;

        int256 actual = defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
        assertEq(actual, 0);
    }

    function test_calculateWeightedPriceReturn_premium() public {
        int256 priceReturn = -1e17; // 10%
        uint256 reserveValue = 34e18;

        // same regardless of direction
        assertEq(
            defaultStrat._calculateWeightedPriceReturn(
                priceReturn, reserveValue, IAutopoolStrategy.RebalanceDirection.In
            ),
            -34e35
        );
        assertEq(
            defaultStrat._calculateWeightedPriceReturn(
                priceReturn, reserveValue, IAutopoolStrategy.RebalanceDirection.Out
            ),
            -34e35
        );
    }

    /* **************************************** */
    /* calculatePriceReturns Tests              */
    /* **************************************** */
    function test_calculatePriceReturns_shouldCapDiscount() public {
        vm.warp(1);
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 59e15; // maxAllowed is 5e16
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 50_000_000_000_000_000);
    }

    // Near half-life
    function test_calculatePriceReturns_shouldDecayDiscountHalf() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 3e16; // maxAllowed is 5e16
        vm.warp(35 days);
        uint40 discountTimestampByPercent;
        discountTimestampByPercent = 1 days;
        lstStat.discountTimestampByPercent = discountTimestampByPercent;
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 14e15);
    }

    // Near quarter-life
    function test_calculatePriceReturns_shouldDecayDiscountQuarter() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 3e16; // maxAllowed is 5e16
        vm.warp(15 days);
        uint40 discountTimestampByPercent = 1 days;
        lstStat.discountTimestampByPercent = discountTimestampByPercent;
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 23e15);
    }

    // Near quarter-life
    function test_calculatePriceReturns_shouldDecayDiscountThreeQuarter() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 3e16; // maxAllowed is 5e16
        vm.warp(60 days);
        uint40 discountTimestampByPercent = 1 days;
        lstStat.discountTimestampByPercent = discountTimestampByPercent;
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 775e13);
    }

    // No decay as the discount is small
    function test_calculatePriceReturns_shouldNotDecayDiscount() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 5e15; // maxAllowed is 5e16
        vm.warp(35 days);
        uint40 discountTimestampByPercent = 1 days;

        lstStat.discountTimestampByPercent = discountTimestampByPercent;
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 5e15);
    }

    /* **************************************** */
    /* calculateIncentiveApr Tests              */
    /* **************************************** */
    function test_calculateIncentiveApr_skipsWorthlessTokens() public {
        address rewardToken = vm.addr(123_456);
        setIncentivePrice(rewardToken, 0, 0);

        address[] memory rewardTokens = new address[](1);
        uint256[] memory annualizedRewards = new uint256[](1);
        rewardTokens[0] = rewardToken;
        IDexLSTStats.StakingIncentiveStats memory stat;
        stat.rewardTokens = rewardTokens;
        stat.annualizedRewardAmounts = annualizedRewards;

        uint256 incentive =
            defaultStrat._calculateIncentiveApr(stat, IAutopoolStrategy.RebalanceDirection.In, vm.addr(1), 1, 1);
        assertEq(incentive, 0);
    }

    function test_calculateIncentiveApr_rebalanceOutShouldExtendIfDestHasCredits() public {
        vm.warp(180 days);
        address lpToken = vm.addr(789);
        setTokenDecimals(lpToken, 18);
        address rewardToken = vm.addr(123_456);
        setIncentivePrice(rewardToken, 1e18, 2e18);
        setTokenDecimals(rewardToken, 18);

        address[] memory rewardTokens = new address[](1);
        uint256[] memory annualizedRewards = new uint256[](1);
        uint40[] memory periodFinishes = new uint40[](1);
        rewardTokens[0] = rewardToken;
        annualizedRewards[0] = 5e18;
        periodFinishes[0] = 180 days - 7 days + 1; // reward can be at most 7 days expired

        IDexLSTStats.StakingIncentiveStats memory stat;
        stat.rewardTokens = rewardTokens;
        stat.annualizedRewardAmounts = annualizedRewards;
        stat.periodFinishForRewards = periodFinishes;
        stat.incentiveCredits = 1; // must be greater than 0 for extension to occur
        stat.safeTotalSupply = 110e18;

        uint256 lpPrice = 12e17;
        uint256 amount = 62e18;
        // totalSupplyInEth = (110 (starting safe supply) - 0 * 62 (amount being removed)) * 1.2 (price) = 132
        // expected apr = 5 (eth per year) / 132 = 3.78%
        uint256 expected = 37_878_787_878_787_878;
        uint256 actual = defaultStrat._calculateIncentiveApr(
            stat, IAutopoolStrategy.RebalanceDirection.Out, lpToken, amount, lpPrice
        );
        assertEq(actual, expected);

        periodFinishes[0] = 180 days - 7 days; // make it so that even with the 7 day bump, still expired
        assertEq(
            defaultStrat._calculateIncentiveApr(
                stat, IAutopoolStrategy.RebalanceDirection.Out, lpToken, amount, lpPrice
            ),
            0
        );
    }

    function test_calculateIncentiveApr_rebalanceOutShouldNotExtendIfNoCredits() public {
        vm.warp(180 days);
        address lpToken = vm.addr(789);
        setTokenDecimals(lpToken, 18);
        address rewardToken = vm.addr(123_456);
        setIncentivePrice(rewardToken, 1e18, 2e18);
        setTokenDecimals(rewardToken, 18);

        address[] memory rewardTokens = new address[](1);
        uint256[] memory annualizedRewards = new uint256[](1);
        uint40[] memory periodFinishes = new uint40[](1);
        rewardTokens[0] = rewardToken;
        annualizedRewards[0] = 5e18;
        periodFinishes[0] = 180 days - 2 days + 1; // reward can be at most 2 days expired

        IDexLSTStats.StakingIncentiveStats memory stat;
        stat.rewardTokens = rewardTokens;
        stat.annualizedRewardAmounts = annualizedRewards;
        stat.periodFinishForRewards = periodFinishes;
        stat.incentiveCredits = 0; // set to zero so expired rewards are ignored

        uint256 incentive =
            defaultStrat._calculateIncentiveApr(stat, IAutopoolStrategy.RebalanceDirection.In, vm.addr(1), 1, 1);
        assertEq(incentive, 0);
    }

    function test_calculateIncentiveApr_rebalanceInHandlesRewardsWhenNoCredits() public {
        vm.warp(180 days);
        address lpToken = vm.addr(789);
        setTokenDecimals(lpToken, 18);
        address rewardToken = vm.addr(123_456);
        setIncentivePrice(rewardToken, 2e18, 2e18); // incentive is worth 2 eth/token
        setTokenDecimals(rewardToken, 18);

        address[] memory rewardTokens = new address[](1);
        uint256[] memory annualizedRewards = new uint256[](1);
        uint40[] memory periodFinishes = new uint40[](1);
        rewardTokens[0] = rewardToken;
        annualizedRewards[0] = 5e18;
        periodFinishes[0] = 180 days + 7 days; // when no credits, rewards must last at least 7 days

        IDexLSTStats.StakingIncentiveStats memory stat;
        stat.rewardTokens = rewardTokens;
        stat.annualizedRewardAmounts = annualizedRewards;
        stat.periodFinishForRewards = periodFinishes;
        stat.incentiveCredits = 0; // set to zero so expired rewards are ignored
        stat.safeTotalSupply = 110e18;

        uint256 lpPrice = 12e17;
        uint256 amount = 62e18;
        // totalSupplyInEth = (110 (starting safe supply) + 62 (amount being removed)) * 1.2 (price) = 206.4
        // expected apr = 10 (eth per year) / 206.4 = 4.84%
        uint256 expected = 48_449_612_403_100_775;
        uint256 actual =
            defaultStrat._calculateIncentiveApr(stat, IAutopoolStrategy.RebalanceDirection.In, lpToken, amount, lpPrice);
        assertEq(actual, expected);

        // test that it gets ignored if less than 7 days
        periodFinishes[0] = 180 days + 7 days - 1;
        assertEq(
            defaultStrat._calculateIncentiveApr(stat, IAutopoolStrategy.RebalanceDirection.In, lpToken, amount, lpPrice),
            0
        );
    }

    // TODO
    function test_calculateIncentiveApr_handlesMultipleRewardTokens() public {
        // one for out rebalance
        // one for in rebalance
    }

    // TODO
    function test_calculateIncentiveApr_handlesDifferentDecimals() public {
        // set lp decimals to not 18
        // one for out rebalance
        // one for in rebalance
    }

    /* **************************************** */
    /* getIncentivePrice Tests                  */
    /* **************************************** */
    function test_getIncentivePrice_returnsMin() public {
        setIncentivePrice(LDO_MAINNET, 20e16, 19e16);
        assertEq(defaultStrat._getIncentivePrice(incentivePricing, LDO_MAINNET), 19e16);
    }

    /* **************************************** */
    /* swapCostOffsetPeriodInDays Tests         */
    /* **************************************** */
    function test_swapCostOffsetPeriodInDays_returnsMinIfExpiredPauseState() public {
        // verify that it starts out set to the init period
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // expiredPauseState exists when there is a pauseTimestamp, but it has expired
        // expiration is 90 days
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days - 1); // must be > 0
        assertFalse(defaultStrat.paused());
        assertTrue(defaultStrat._expiredPauseState());

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 10);
    }

    function test_swapCostOffsetPeriodInDays_relaxesCorrectly() public {
        // verify that it starts out set to the init period
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);
        assertEq(defaultStrat.lastRebalanceTimestamp(), startBlockTime - defaultStrat.rebalanceTimeGapInSeconds());

        // swapOffset is relaxed every 20 days in the test config
        // we want 4 relaxes to occur 20 * 4 + 1 = 81, set to 90 to ensure truncation occurs
        vm.warp(startBlockTime + 90 days);

        // each relax step is 3 days, so the expectation is 4 * 3 = 12 days
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 12 + 28);

        // init is 28 days and max is 60 days, to hit the max we need 10.67 relax periods = 213.33 days
        // exceed that to test that the swapOffset is limited to the max
        vm.warp(startBlockTime + 300 days);
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 60);
    }

    /* **************************************** */
    /* pause Tests                              */
    /* **************************************** */
    function test_pause_returnsFalseWhenZero() public {
        defaultStrat._setPausedTimestamp(0); // ensure it is zero
        assertFalse(defaultStrat.paused());
    }

    function test_pause_returnsFalseWhenPauseIsExpired() public {
        // pause expires after 90 days
        vm.warp(100 days);
        defaultStrat._setPausedTimestamp(10 days - 1);

        assertFalse(defaultStrat.paused());
    }

    function test_pause_returnsTrueWhenPaused() public {
        // pause expires after 90 days
        vm.warp(100 days);
        defaultStrat._setPausedTimestamp(10 days);

        assertTrue(defaultStrat.paused());
    }

    /* **************************************** */
    /* navUpdate Tests                          */
    /* **************************************** */
    function test_navUpdate_RevertIf_notAutopoolETH() public {
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.NotAutopoolETH.selector));
        defaultStrat.navUpdate(100e18);
    }

    function test_navUpdate_shouldUpdateNavTracking() public {
        vm.startPrank(mockAutopoolETH);
        vm.warp(1 days);
        defaultStrat.navUpdate(1e18);
        vm.warp(2 days);
        defaultStrat.navUpdate(2e18);
        vm.stopPrank();

        NavTracking.State memory state = defaultStrat._getNavTrackingState();
        assertEq(state.getDaysAgo(0), 2e18);
        assertEq(state.getDaysAgo(1), 1e18);
    }

    function test_navUpdate_shouldClearExpiredPause() public {
        // setup the expiredPauseState
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days - 1); // must be > 0
        assertTrue(defaultStrat._expiredPauseState());

        vm.prank(mockAutopoolETH);
        defaultStrat.navUpdate(10e18);

        assertFalse(defaultStrat._expiredPauseState());
    }

    function test_navUpdate_shouldPauseIfDecay() public {
        // reduced to the lookback for testing purposes only
        AutopoolETHStrategyConfig.StrategyConfig memory config = helpers.getDefaultConfig();
        config.navLookback.lookback1InDays = 1;
        config.navLookback.lookback2InDays = 2;
        config.navLookback.lookback3InDays = 3;

        AutopoolETHStrategyHarness strat = deployStrategy(config);

        vm.startPrank(mockAutopoolETH);
        vm.warp(1 days);
        strat.navUpdate(10e18);
        vm.warp(2 days);
        strat.navUpdate(11e18);
        vm.warp(3 days);
        strat.navUpdate(12e18);

        // verify that the strategy is NOT paused
        assertFalse(strat.paused());

        vm.warp(4 days);
        strat.navUpdate(9e18); // less than the 3 prior recordings

        // last nav data point triggers pause state
        assertTrue(strat.paused());
        assertEq(strat.lastPausedTimestamp(), 4 days);
    }

    function test_navUpdate_shouldNotUpdatePauseTimestampIfAlreadyPaused() public {
        // reduced to the lookback for testing purposes only
        AutopoolETHStrategyConfig.StrategyConfig memory config = helpers.getDefaultConfig();
        config.navLookback.lookback1InDays = 1;
        config.navLookback.lookback2InDays = 2;
        config.navLookback.lookback3InDays = 3;

        AutopoolETHStrategyHarness strat = deployStrategy(config);

        vm.startPrank(mockAutopoolETH);
        vm.warp(1 days);
        strat.navUpdate(10e18);
        vm.warp(2 days);
        strat.navUpdate(11e18);
        vm.warp(3 days);
        strat.navUpdate(12e18);

        // verify that the strategy is NOT paused
        assertFalse(strat.paused());

        vm.warp(4 days);
        strat.navUpdate(9e18); // less than the 3 prior recordings
        assertTrue(strat.paused());
        assertEq(strat.lastPausedTimestamp(), 4 days);

        vm.warp(5 days);
        strat.navUpdate(8e18);
        assertTrue(strat.paused());
        assertEq(strat.lastPausedTimestamp(), 4 days);
    }

    /* **************************************** */
    /* rebalanceSuccessfullyExecuted Tests      */
    /* **************************************** */
    function test_rebalanceSuccessfullyExecuted_RevertIf_notAutopoolVault() public {
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.NotAutopoolETH.selector));
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    }

    function test_rebalanceSuccessfullyExecuted_clearsExpiredPause() public {
        // verify that it's at the init value
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // setup the expiredPauseState
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days - 1); // must be > 0
        assertTrue(defaultStrat._expiredPauseState());

        vm.prank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        // after clearing the expired pause, swapCostOffset == min
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 10);
        assertFalse(defaultStrat._expiredPauseState());
    }

    function test_rebalanceSuccessfullyExecuted_updatesSwapCostOffset() public {
        // verify that it's at the init value
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // loosen the swapCostOffset to verify it gets picked up
        // lastRebalanceTimestamp = 1;
        // move forward 45 days = 2 relax steps -> 2 * 3 (relaxStep) + 28 (init) = 34
        vm.warp(startBlockTime + 46 days);

        vm.prank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 34);
    }

    function test_rebalanceSuccessfullyExecuted_updatesLastRebalanceTimestamp() public {
        // verify it is at the initialized value
        assertEq(defaultStrat.lastRebalanceTimestamp(), startBlockTime - defaultStrat.rebalanceTimeGapInSeconds());

        vm.warp(startBlockTime + 23 days);
        vm.prank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.lastRebalanceTimestamp(), startBlockTime + 23 days);
    }

    function test_rebalanceSuccessfullyExecuted_updatesDestinationLastRebalanceTimestamp() public {
        // verify it is at the initialized value
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 0);

        vm.warp(startBlockTime + 23 days);
        vm.prank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), startBlockTime + 23 days);
    }

    function test_rebalanceSuccessfullyExecuted_updatesViolationTracking() public {
        // move the system to block.timestamp that is beyond the maxOffset
        // since timestamps are well beyond 60 days in seconds this is a OK
        // and avoids initialization scenario where a violation is tracked b/c timestamp - 0 < offset
        defaultStrat._setLastRebalanceTimestamp(60 days);
        vm.warp(60 days);

        vm.startPrank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 60 days);

        // SETUP TO GET VIOLATION
        // add to dest = 60 days
        // swapCostOffset = 28 days at init
        // the minimum to not create a violation is: 60 (start) + 28 (initOffset) + 3 days (1x relax) = 91 days

        // flip the direction of the rebalance
        defaultParams.destinationIn = mockOutDest;
        defaultParams.destinationOut = mockInDest;

        uint256 newTimestamp = 91 days - 1; // set to 1 second less to get a violation
        vm.warp(newTimestamp);
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 31);

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 60 days);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockOutDest), newTimestamp);

        ViolationTracking.State memory state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 2);
        assertEq(state.violationCount, 1);

        // SETUP TO NOT GET VIOLATION
        // add to dest = 91 days - 1
        // swapCostOffset = 31 days + 1x relax = 34 days
        // the minimum to not create a violation is: 91days - 1s + 34days (offset) = 125 days - 1s

        // flip the direction of the rebalance again
        defaultParams.destinationIn = mockInDest;
        defaultParams.destinationOut = mockOutDest;

        newTimestamp = 125 days - 1;
        vm.warp(newTimestamp);
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 34);

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockOutDest), 91 days - 1);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), newTimestamp);

        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 3);
        assertEq(state.violationCount, 1);
    }

    function test_rebalanceSuccessfullyExecuted_tightensSwapCostOffset() public {
        // move the system to block.timestamp that is beyond the maxOffset
        // since timestamps are well beyond 60 days in seconds this is a OK
        // and avoids initialization scenario where a violation is tracked b/c timestamp - 0 < offset
        defaultStrat._setLastRebalanceTimestamp(60 days);
        vm.warp(60 days);

        vm.startPrank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 60 days);

        // flip the direction of the rebalance
        defaultParams.destinationIn = mockOutDest;
        defaultParams.destinationOut = mockInDest;

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // generate 5 violations by removing from the same destination repeatedly at the same timestamp
        // after this there are 6 total rebalances tracked
        for (uint256 i = 0; i < 5; ++i) {
            defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        }

        ViolationTracking.State memory state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 6);
        assertEq(state.violationCount, 5);

        // we're only going to add to the same destination with this config to not generate violations
        IStrategy.RebalanceParams memory nonViolationParams = getDefaultRebalanceParams();
        nonViolationParams.destinationIn = vm.addr(999_999);
        nonViolationParams.destinationOut = vm.addr(888_888);

        for (uint256 y = 0; y < 4; ++y) {
            defaultStrat.rebalanceSuccessfullyExecuted(nonViolationParams);
        }

        // tighten step is 3 day, so we should be at 28 - 3 = 25
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 25);

        // verify that violation tracking was reset on the tightening
        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);
        assertEq(state.violations, 0);
    }

    function test_rebalanceSuccessfullyExecuted_tightenMin() public {
        // move the system to block.timestamp that is beyond the maxOffset
        // since timestamps are well beyond 60 days in seconds this is a OK
        // and avoids initialization scenario where a violation is tracked b/c timestamp - 0 < offset
        defaultStrat._setLastRebalanceTimestamp(60 days);
        vm.warp(60 days);

        vm.startPrank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 60 days);

        // flip the direction of the rebalance
        defaultParams.destinationIn = mockOutDest;
        defaultParams.destinationOut = mockInDest;

        // current swapOffset = 28 days; min = 10
        // (28-10) / 3 = 6 tightens to bring to min
        assertEq(defaultStrat.swapCostOffsetTightenStepInDays(), 3);
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // generate 6 tightens
        for (uint256 i = 1; i < 60; ++i) {
            defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        }

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 10);

        // generate one more now that we're at the limit
        for (uint256 y = 0; y < 10; ++y) {
            defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        }

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 10);
    }

    function test_rebalanceSuccessfullyExecuted_ignoreRebalancesFromIdle() public {
        // advance so we can make sure that non-idle timestamp is updated
        vm.warp(startBlockTime + 60 days);

        ViolationTracking.State memory state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        // idle -> destination
        defaultParams.destinationOut = mockAutopoolETH;
        defaultParams.destinationIn = mockInDest;

        vm.startPrank(mockAutopoolETH);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        // check other direction since it skips both in/out of idle
        // destination -> idle
        defaultParams.destinationOut = mockInDest;
        defaultParams.destinationIn = mockAutopoolETH;

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        assertEq(defaultStrat.lastAddTimestampByDestination(mockAutopoolETH), 0);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), startBlockTime + 60 days);
    }

    /* **************************************** */
    /* ensureNotStaleData Tests                 */
    /* **************************************** */
    function test_ensureNotStaleData_RevertIf_dataIsStale() public {
        vm.warp(90 days);
        uint256 dataTimestamp = 88 days - 1; // tolerance is 2 days

        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.StaleData.selector, "data"));
        defaultStrat._ensureNotStaleData("data", dataTimestamp);
    }

    function test_ensureNotStaleData_noRevertWhenNotStale() public {
        vm.warp(90 days);
        uint256 dataTimestamp = 88 days; // tolerance is 2 days

        defaultStrat._ensureNotStaleData("data", dataTimestamp);
    }

    /* **************************************** */
    /* setLstPriceGapTolerance Tests            */
    /* **************************************** */

    function test_setLstPriceGapTolerance_OnlyCallableByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        defaultStrat.setLstPriceGapTolerance(100);

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setLstPriceGapTolerance(100);
    }

    function test_setLstPriceGapTolerance_UpdatesValue() public {
        uint256 originalValue = defaultStrat.lstPriceGapTolerance();

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setLstPriceGapTolerance(100);

        assertTrue(originalValue != 100, "originalValue");
        assertEq(defaultStrat.lstPriceGapTolerance(), 100, "newValue");
    }

    function test_setLstPriceGapTolerance_EmitsEvent() public {
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit LstPriceGapSet(100);
        defaultStrat.setLstPriceGapTolerance(100);
    }

    /* **************************************** */
    /* setDustPositionPortions Tests            */
    /* **************************************** */

    function test_setDustPositionPortions_OnlyCallableByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        defaultStrat.setDustPositionPortions(100);

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setDustPositionPortions(100);
    }

    function test_setDustPositionPortions_UpdatesValue() public {
        uint256 originalValue = defaultStrat.dustPositionPortions();

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setDustPositionPortions(100);

        assertTrue(originalValue != 100, "originalValue");
        assertEq(defaultStrat.dustPositionPortions(), 100, "newValue");
    }

    function test_setDustPositionPortions_EmitsEvent() public {
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit DustPositionPortionSet(100);
        defaultStrat.setDustPositionPortions(100);
    }

    /* **************************************** */
    /* setIdleThreshold Tests            */
    /* **************************************** */

    function test_setIdleThreshold_OnlyCallableByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        defaultStrat.setIdleThresholds(4e16, 6e16);

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setIdleThresholds(4e16, 6e16);
    }

    function test_setIdleThresholdError() public {
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));
        // Low > High
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InconsistentIdleThresholds.selector));
        defaultStrat.setIdleThresholds(6e16, 3e16);
        // Only one of low & high is set to 0
        vm.expectRevert(abi.encodeWithSelector(AutopoolETHStrategy.InconsistentIdleThresholds.selector));
        defaultStrat.setIdleThresholds(0, 3e16);
    }

    function test_setIdleThresholds_UpdatesValue() public {
        uint256 originalLowValue = defaultStrat.idleLowThreshold();
        uint256 originalHighValue = defaultStrat.idleHighThreshold();

        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        defaultStrat.setIdleThresholds(5e16, 8e16);

        assertTrue(originalLowValue != 5e16, "originalValue");
        assertEq(defaultStrat.idleLowThreshold(), 5e16, "newValue");
        assertTrue(originalHighValue != 8e16, "originalValue");
        assertEq(defaultStrat.idleHighThreshold(), 8e16, "newValue");
    }

    function test_setIdleThresholds_EmitsEvent() public {
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit IdleThresholdsSet(4e16, 7e16);
        defaultStrat.setIdleThresholds(4e16, 7e16);
    }

    /* **************************************** */
    /* Test Helpers                             */
    /* **************************************** */

    function deployStrategy(AutopoolETHStrategyConfig.StrategyConfig memory cfg)
        internal
        returns (AutopoolETHStrategyHarness strat)
    {
        AutopoolETHStrategyHarness stratHarness =
            new AutopoolETHStrategyHarness(ISystemRegistry(address(systemRegistry)), cfg);
        strat = AutopoolETHStrategyHarness(Clones.clone(address(stratHarness)));
        strat.initialize(mockAutopoolETH);
    }

    // rebalance params that will pass validation
    function getDefaultRebalanceParams() internal view returns (IStrategy.RebalanceParams memory params) {
        params = IStrategy.RebalanceParams({
            destinationIn: mockInDest,
            tokenIn: mockInToken,
            amountIn: 10e18,
            destinationOut: mockOutDest,
            tokenOut: mockOutToken,
            amountOut: 10e18
        });
    }

    /* **************************************** */
    /* AutopoolETH Mocks                           */
    /* **************************************** */
    function setAutopoolDefaultMocks() private {
        setAutopoolVaultIsShutdown(false);
        setAutopoolVaultBaseAsset(mockBaseAsset);
        setAutopoolDestQueuedForRemoval(mockInDest, false);
        setAutopoolDestQueuedForRemoval(mockOutDest, false);
        setAutopoolIdle(100e18); // 100 eth
        setAutopoolSystemRegistry(address(systemRegistry));
        setAutopoolDestinationRegistered(mockInDest, true);
        setAutopoolDestinationRegistered(mockOutDest, true);
    }

    function setAutopoolVaultIsShutdown(bool shutdown) private {
        vm.mockCall(mockAutopoolETH, abi.encodeWithSelector(IAutopool.isShutdown.selector), abi.encode(shutdown));
    }

    function setAutopoolVaultBaseAsset(address asset) private {
        vm.mockCall(mockAutopoolETH, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));
    }

    function setAutopoolDestQueuedForRemoval(address dest, bool isRemoved) private {
        vm.mockCall(
            mockAutopoolETH,
            abi.encodeWithSelector(IAutopool.isDestinationQueuedForRemoval.selector, dest),
            abi.encode(isRemoved)
        );
    }

    function setAutopoolIdle(uint256 amount) private {
        vm.mockCall(
            mockAutopoolETH,
            abi.encodeWithSelector(IAutopool.getAssetBreakdown.selector),
            abi.encode(IAutopool.AssetBreakdown({ totalIdle: amount, totalDebt: 0, totalDebtMin: 0, totalDebtMax: 0 }))
        );
    }

    function setAutopoolDestInfo(address dest, AutopoolDebt.DestinationInfo memory info) private {
        // split up in order to get around formatter issue
        bytes4 selector = IAutopool.getDestinationInfo.selector;
        vm.mockCall(mockAutopoolETH, abi.encodeWithSelector(selector, dest), abi.encode(info));
    }

    function setAutopoolTotalAssets(uint256 amount) private {
        vm.mockCall(mockAutopoolETH, abi.encodeWithSelector(IERC4626.totalAssets.selector), abi.encode(amount));
    }

    function setAutopoolSystemRegistry(address _systemRegistry) private {
        vm.mockCall(
            mockAutopoolETH,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(_systemRegistry)
        );
    }

    function setAutopoolDestinationRegistered(address dest, bool isRegistered) private {
        vm.mockCall(
            mockAutopoolETH,
            abi.encodeWithSelector(IAutopool.isDestinationRegistered.selector, dest),
            abi.encode(isRegistered)
        );
    }

    /* **************************************** */
    /* Destination Mocks                        */
    /* **************************************** */
    function setInDestDefaultMocks() private {
        setDestinationUnderlying(mockInDest, mockInToken);
        address[] memory underlyingLSTs = new address[](1);
        underlyingLSTs[0] = mockInLSTToken;
        setDestinationUnderlyingTokens(mockInDest, underlyingLSTs);
        setDestinationIsShutdown(mockInDest, false);
        setDestinationStats(mockInDest, mockInStats);
        setAutopoolDestinationBalanceOf(mockInDest, 100e18);
        setTokenDecimals(mockInDest, 18);
        setDestinationGetPool(mockInDest, address(0));
    }

    function setOutDestDefaultMocks() private {
        setDestinationUnderlying(mockOutDest, mockOutToken);
        address[] memory underlyingLSTs = new address[](1);
        underlyingLSTs[0] = mockOutLSTToken;
        setDestinationUnderlyingTokens(mockOutDest, underlyingLSTs);
        setDestinationIsShutdown(mockOutDest, false);
        setDestinationStats(mockOutDest, mockOutStats);
        setAutopoolDestinationBalanceOf(mockOutDest, 100e18);
        setTokenDecimals(mockOutDest, 18);
        setDestinationGetPool(mockOutDest, address(0));
    }

    function setDestinationUnderlying(address dest, address underlying) private {
        vm.mockCall(dest, abi.encodeWithSelector(IDestinationVault.underlying.selector), abi.encode(underlying));
    }

    function setDestinationUnderlyingTokens(address dest, address[] memory underlyingLSTs) private {
        vm.mockCall(
            dest, abi.encodeWithSelector(IDestinationVault.underlyingTokens.selector), abi.encode(underlyingLSTs)
        );
    }

    function setDestinationGetPool(address dest, address poolAddress) private {
        vm.mockCall(dest, abi.encodeWithSelector(IDestinationVault.getPool.selector), abi.encode(poolAddress));
    }

    function setDestinationIsShutdown(address dest, bool shutdown) private {
        vm.mockCall(dest, abi.encodeWithSelector(IDestinationVault.isShutdown.selector), abi.encode(shutdown));
    }

    function setDestinationStats(address dest, address stats) private {
        vm.mockCall(dest, abi.encodeWithSelector(IDestinationVault.getStats.selector), abi.encode(stats));
    }

    function setAutopoolDestinationBalanceOf(address dest, uint256 amount) private {
        vm.mockCall(
            dest, abi.encodeWithSelector(IERC20.balanceOf.selector, address(mockAutopoolETH)), abi.encode(amount)
        );
    }

    function setDestinationDebtValue(address dest, uint256 shares, uint256 amount) private {
        vm.mockCall(dest, abi.encodeWithSignature("debtValue(uint256)", shares), abi.encode(amount));
    }

    /* **************************************** */
    /* Stats Mocks                              */
    /* **************************************** */
    function setStatsCurrent(address stats, IDexLSTStats.DexLSTStatsData memory result) private {
        vm.mockCall(stats, abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(result));
    }

    /* **************************************** */
    /* LP Token Mocks                           */
    /* **************************************** */
    function setTokenDefaultMocks() private {
        setDestinationSafePrice(mockInDest, 1e18);
        setDestinationSpotPrice(mockInDest, 1e18);
        setTokenPrice(mockInLSTToken, 1e18);
        setTokenSpotPrice(mockInLSTToken, 1e18);
        setTokenDecimals(mockInToken, 18);
        setDestinationSafePrice(mockOutDest, 1e18);
        setDestinationSpotPrice(mockOutDest, 1e18);
        setTokenPrice(mockOutLSTToken, 1e18);
        setTokenSpotPrice(mockOutLSTToken, 1e18);
        setTokenDecimals(mockOutToken, 18);
        setTokenPrice(mockBaseAsset, 1e18);
        setTokenSpotPrice(mockBaseAsset, 1e18);
        setTokenDecimals(mockBaseAsset, 18);
    }

    /* **************************************** */
    /* Helper Mocks                        */
    /* **************************************** */
    function setDestinationSpotPrice(address destination, uint256 price) private {
        vm.mockCall(
            address(destination),
            abi.encodeWithSelector(IDestinationVault.getValidatedSpotPrice.selector),
            abi.encode(price)
        );
    }

    function setTokenPrice(address token, uint256 price) private {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function setDestinationSafePrice(address destination, uint256 price) private {
        vm.mockCall(
            address(destination),
            abi.encodeWithSelector(IDestinationVault.getValidatedSafePrice.selector),
            abi.encode(price)
        );
    }

    function setTokenSpotPrice(address token, uint256 price) private {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getSpotPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function setTokenDecimals(address token, uint8 decimals) private {
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
    }

    function setIncentivePricing() private {
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.incentivePricing.selector),
            abi.encode(incentivePricing)
        );
    }

    function setIncentivePrice(address token, uint256 fastPrice, uint256 slowPrice) private {
        vm.mockCall(
            address(incentivePricing),
            abi.encodeWithSelector(IIncentivesPricingStats.getPriceOrZero.selector, token, 2 days),
            abi.encode(fastPrice, slowPrice)
        );
    }
}

contract AutopoolETHStrategyHarness is AutopoolETHStrategy {
    constructor(
        ISystemRegistry _systemRegistry,
        AutopoolETHStrategyConfig.StrategyConfig memory conf
    ) AutopoolETHStrategy(_systemRegistry, conf) { }

    function init(address autoPool) public {
        _initialize(autoPool);
    }

    function _validateRebalanceParams(IStrategy.RebalanceParams memory params) public view {
        validateRebalanceParams(params);
    }

    function _getRebalanceValueStats(IStrategy.RebalanceParams memory params)
        public
        returns (SummaryStats.RebalanceValueStats memory)
    {
        return SummaryStats.getRebalanceValueStats(params, address(autoPool));
    }

    function _verifyRebalanceToIdle(IStrategy.RebalanceParams memory params, uint256 slippage) public {
        verifyRebalanceToIdle(params, slippage);
    }

    function _getDestinationTrimAmount(IDestinationVault dest) public returns (uint256) {
        return getDestinationTrimAmount(dest);
    }

    function _getDiscountAboveThreshold(
        uint24[10] memory discountHistory,
        uint256 threshold1,
        uint256 threshold2
    ) public pure returns (uint256 count1, uint256 count2) {
        return getDiscountAboveThreshold(discountHistory, threshold1, threshold2);
    }

    function _verifyTrimOperation(IStrategy.RebalanceParams memory params, uint256 trimAmount) public returns (bool) {
        return verifyTrimOperation(params, trimAmount);
    }

    function _setPausedTimestamp(uint40 timestamp) public {
        lastPausedTimestamp = timestamp;
    }

    function _ensureNotStaleData(string memory name, uint256 dataTimestamp) public view {
        ensureNotStaleData(name, dataTimestamp);
    }

    function _expiredPauseState() public view returns (bool) {
        return expiredPauseState();
    }

    function _setLastRebalanceTimestamp(uint40 timestamp) public {
        lastRebalanceTimestamp = timestamp;
    }

    function _getNavTrackingState() public view returns (NavTracking.State memory) {
        return navTrackingState;
    }

    function _getViolationTrackingState() public view returns (ViolationTracking.State memory) {
        return violationTrackingState;
    }

    function _calculatePriceReturns(IDexLSTStats.DexLSTStatsData memory stats) public view returns (int256[] memory) {
        return PriceReturn.calculatePriceReturns(stats);
    }

    function _calculateIncentiveApr(
        IDexLSTStats.StakingIncentiveStats memory stats,
        RebalanceDirection direction,
        address destAddress,
        uint256 amount,
        uint256 price
    ) public view returns (uint256) {
        return Incentives.calculateIncentiveApr(
            systemRegistry.incentivePricing(), stats, direction, destAddress, amount, price
        );
    }

    function _getIncentivePrice(IIncentivesPricingStats pricing, address token) public view returns (uint256) {
        return Incentives.getIncentivePrice(staleDataToleranceInSeconds, pricing, token);
    }

    function _getRebalanceInSummaryStats(IStrategy.RebalanceParams memory rebalanceParams)
        public
        returns (IStrategy.SummaryStats memory inSummary)
    {
        inSummary = getRebalanceInSummaryStats(rebalanceParams);
    }

    function _getDestinationSummaryStats(
        address destAddress,
        uint256 price,
        RebalanceDirection direction,
        uint256 amount
    ) public returns (IStrategy.SummaryStats memory) {
        return SummaryStats.getDestinationSummaryStats(
            autoPool, systemRegistry.incentivePricing(), destAddress, price, direction, amount
        );
    }

    function _calculateWeightedPriceReturn(
        int256 priceReturn,
        uint256 reserveValue,
        RebalanceDirection direction
    ) public view returns (int256) {
        return PriceReturn.calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
    }
}

contract MockHook is ISummaryStatsHook {
    function execute(
        IStrategy.SummaryStats memory _result,
        IAutopool,
        address,
        uint256,
        IAutopoolStrategy.RebalanceDirection,
        uint256
    ) external pure override returns (IStrategy.SummaryStats memory result) {
        result = _result;

        // Increment pricePerShare.  Doing this as it is not manipulated within getDestinationSummaryStats, just set
        result.pricePerShare++;
    }
}
