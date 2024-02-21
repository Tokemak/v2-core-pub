// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { LMPStrategy, ISystemRegistry } from "src/strategy/LMPStrategy.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { TOKE_MAINNET, WETH_MAINNET, LDO_MAINNET } from "test/utils/Addresses.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { LMPStrategyTestHelpers as helpers } from "test/strategy/LMPStrategyTestHelpers.sol";
import { Errors } from "src/utils/Errors.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { NavTracking } from "src/strategy/NavTracking.sol";
import { ViolationTracking } from "src/strategy/ViolationTracking.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";

// solhint-disable func-name-mixedcase

contract LMPStrategyTest is Test {
    using NavTracking for NavTracking.State;

    address private mockLMPVault = vm.addr(900);
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

    LMPStrategyHarness private defaultStrat;
    IStrategy.RebalanceParams private defaultParams;
    IStrategy.SummaryStats private destOut;

    function setUp() public {
        vm.label(mockLMPVault, "lmpVault");
        vm.label(mockBaseAsset, "baseAsset");
        vm.label(mockInDest, "inDest");
        vm.label(mockInToken, "inToken");
        vm.label(mockOutDest, "outDest");
        vm.label(mockOutToken, "outToken");

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        setLmpDefaultMocks();

        defaultStrat = deployStrategy(helpers.getDefaultConfig());
        defaultParams = getDefaultRebalanceParams();

        setInDestDefaultMocks();
        setOutDestDefaultMocks();
        setTokenDefaultMocks();
        setIncentivePricing();
    }

    /* **************************************** */
    /* constructor Tests                    */
    /* **************************************** */
    function test_constructor_RevertIf_lmpVaultZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_lmpVault"));
        new LMPStrategyHarness(ISystemRegistry(address(systemRegistry)), address(0), helpers.getDefaultConfig());
    }

    // function test_constructor_RevertIf_systemRegistryMismatch() public {
    //     setLmpSystemRegistry(address(1));
    //     vm.expectRevert(abi.encodeWithSelector(LMPStrategy.SystemRegistryMismatch.selector));
    //     defaultStrat = deployStrategy(helpers.getDefaultConfig());
    // }

    function test_constructor_RevertIf_invalidConfig() public {
        // this test only tests a single failure to ensure that config validation is occurring
        // in the constructor. All other config validation tests are in LMPStrategyConfig tests
        LMPStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();

        // set init < min to trigger a failure
        cfg.swapCostOffset.initInDays = 10;
        cfg.swapCostOffset.minInDays = 11;
        vm.expectRevert(abi.encodeWithSelector(LMPStrategyConfig.InvalidConfig.selector, "swapCostOffsetPeriodInit"));
        defaultStrat = deployStrategy(cfg);
    }

    /* **************************************** */
    /* verifyRebalance Tests                    */
    /* **************************************** */
    function test_verifyRebalance_success() public {
        vm.warp(180 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setLmpDestinationBalanceOf(mockOutDest, 200e18);

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

    function test_verifyLSTPriceGap_Revert() public {
        // this test verifies that revert logic is followed based on tolerance
        // of safe-spot price for LST
        setTokenSpotPrice(mockOutLSTToken, 99e16); // set spot OutToken price slightly lower than safe
        setTokenSpotPrice(mockInLSTToken, 101e16); // set spot OutToken price slightly higher than safe
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.LSTPriceGapToleranceExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        setTokenSpotPrice(mockOutLSTToken, 99.89e16); // set spot price slightly lower than safe near tolerance
        setTokenSpotPrice(mockInLSTToken, 100e16); // set spot = safe
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.LSTPriceGapToleranceExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_invalidParams() public {
        // this test ensures that `validateRebalanceParams` is called. It is not exhaustive
        defaultParams.amountIn = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amountIn"));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_invalidRebalanceToIdle() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from LMP

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // set the in token to idle
        defaultParams.destinationIn = mockLMPVault;
        defaultParams.tokenIn = mockBaseAsset;

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_returnTrueOnValidRebalanceToIdleCleanUpDust() public {
        // make the strategy paused to ensure that rebalances to idle can still occur
        setDestinationIsShutdown(mockOutDest, false); // force trim
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from LMP
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 90e17;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 99e17, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 90e17, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 90e17;
        defaultParams.amountIn = 90e17;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 90e17, 99e17);

        // set the in token to idle
        defaultParams.destinationIn = mockLMPVault;
        defaultParams.tokenIn = mockBaseAsset;

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_returnTrueOnValidRebalanceToIdle() public {
        // make the strategy paused to ensure that rebalances to idle can still occur
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(10 days);

        setDestinationIsShutdown(mockOutDest, true); // force trim
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from LMP
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 91 days,
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // set the in token to idle
        defaultParams.destinationIn = mockLMPVault;
        defaultParams.tokenIn = mockBaseAsset;

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_RevertIf_paused() public {
        // pause config is for 90 days, so set block.timestamp - pauseTimestamp = 90 days
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.StrategyPaused.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_maxSlippageExceeded() public {
        // max slippage on a normal swap is 1%
        // token prices are set 1:1 with eth, so to get 1% slippage adjust the in/out values
        defaultParams.amountIn = 989e17; // 98.9
        defaultParams.amountOut = 100e18; // 100

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_maxDiscountOrPremiumExceeded() public {
        vm.warp(180 days);

        // setup for maxDiscount check
        IDexLSTStats.DexLSTStatsData memory inStats;
        inStats.lastSnapshotTimestamp = 180 days;
        inStats.reservesInEth = new uint256[](1);
        inStats.reservesInEth[0] = 1e18;
        inStats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        ILSTStats.LSTStatsData memory lstStat;
        lstStat.lastSnapshotTimestamp = 180 days;
        lstStat.discount = 0.021e18; // above 2% max discount
        inStats.lstStatsData[0] = lstStat;
        setStatsCurrent(mockInStats, inStats);

        IDexLSTStats.DexLSTStatsData memory outStats;
        outStats.lastSnapshotTimestamp = 180 days;
        setStatsCurrent(mockOutStats, outStats);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxDiscountExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        // setup for maxPremium check
        lstStat.discount = -0.011e18; // above 1% max premium
        setStatsCurrent(mockInStats, inStats);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxPremiumExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);
    }

    function test_verifyRebalance_RevertIf_swapCostTooHigh() public {
        vm.warp(180 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setLmpDestinationBalanceOf(mockOutDest, 200e18);

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
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.SwapCostExceeded.selector));
        defaultStrat.verifyRebalance(defaultParams, destOut);

        // verify that it gets let through just above the required swapCost
        inStats.feeApr = 0.095656855707106964e18; // increment failing apr by 1
        setStatsCurrent(mockInStats, inStats);

        (bool success,) = defaultStrat.verifyRebalance(defaultParams, destOut);
        assertTrue(success);
    }

    function test_verifyRebalance_RevertIf_swapCostTooHighSameToken() public {
        vm.warp(180 days);
        defaultStrat._setLastRebalanceTimestamp(180 days);

        // ensure the vault has enough assets
        setLmpDestinationBalanceOf(mockOutDest, 200e18);

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
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.SwapCostExceeded.selector));
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

    function test_updateWithdrawalQueueAfterRebalance_betweenDestinations() public {
        vm.prank(mockLMPVault);
        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueHead, defaultParams.destinationOut), 1
        );
        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueTail, defaultParams.destinationIn), 1
        );

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    }

    function test_updateWithdrawalQueueAfterRebalance_fromIdle() public {
        defaultParams.destinationOut = address(mockLMPVault);

        vm.prank(mockLMPVault);

        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueHead, defaultParams.destinationOut), 0
        );
        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueTail, defaultParams.destinationIn), 1
        );

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    }

    function test_updateWithdrawalQueueAfterRebalance_toIdle() public {
        defaultParams.destinationIn = address(mockLMPVault);

        vm.prank(mockLMPVault);

        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueHead, defaultParams.destinationOut), 1
        );
        vm.expectCall(
            address(mockLMPVault), abi.encodeCall(ILMPVault.addToWithdrawalQueueTail, defaultParams.destinationIn), 0
        );

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    }

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
        setLmpDestinationRegistered(defaultParams.destinationIn, false);
        vm.expectRevert(
            abi.encodeWithSelector(LMPStrategy.UnregisteredDestination.selector, defaultParams.destinationIn)
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destinationOutNotRegistered() public {
        setLmpDestinationRegistered(defaultParams.destinationOut, false);
        vm.expectRevert(
            abi.encodeWithSelector(LMPStrategy.UnregisteredDestination.selector, defaultParams.destinationOut)
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_handlesQueuedForRemoval() public {
        // set both destinations as only queued for removal
        setLmpDestinationRegistered(defaultParams.destinationOut, false);
        setLmpDestQueuedForRemoval(defaultParams.destinationOut, true);
        setLmpDestinationRegistered(defaultParams.destinationIn, false);
        setLmpDestQueuedForRemoval(defaultParams.destinationIn, true);

        // expect not to revert
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_handlesIdle() public {
        // set in == idle
        defaultParams.destinationIn = mockLMPVault;
        defaultParams.tokenIn = mockBaseAsset;

        // ensure that the lmpVault is not registered
        setLmpDestinationRegistered(defaultParams.destinationIn, false);

        // expect this not to revert
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_lmpShutdownAndNotIdle() public {
        setLmpVaultIsShutdown(true);
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.OnlyRebalanceToIdleAvailable.selector));

        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destinationsMatch() public {
        setLmpDestinationRegistered(vm.addr(1), true);
        defaultParams.destinationIn = vm.addr(1);
        defaultParams.destinationOut = vm.addr(1);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.RebalanceDestinationsMatch.selector));
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destInIsVaultButTokenNotBase() public {
        // this means we're expecting the baseAsset as the return token
        defaultParams.destinationIn = mockLMPVault;

        vm.expectRevert(
            abi.encodeWithSelector(
                LMPStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                mockLMPVault,
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
                LMPStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                defaultParams.destinationIn,
                mockInToken,
                defaultParams.tokenIn
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destInOutVaultButTokenNotBase() public {
        // this means we're expecting the baseAsset as the return token
        defaultParams.destinationOut = mockLMPVault;

        vm.expectRevert(
            abi.encodeWithSelector(
                LMPStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                mockLMPVault,
                defaultParams.tokenOut,
                mockBaseAsset
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutInsufficientIdle() public {
        defaultParams.destinationOut = mockLMPVault;
        defaultParams.tokenOut = mockBaseAsset;

        setLmpIdle(defaultParams.amountOut - 1);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.InsufficientAssets.selector, mockBaseAsset));
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutUnderlyingMismatch() public {
        defaultParams.tokenOut = vm.addr(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                LMPStrategy.RebalanceDestinationUnderlyerMismatch.selector,
                defaultParams.destinationOut,
                mockOutToken,
                defaultParams.tokenOut
            )
        );
        defaultStrat._validateRebalanceParams(defaultParams);
    }

    function test_validateRebalanceParams_RevertIf_destOutInsufficient() public {
        setLmpDestinationBalanceOf(mockOutDest, defaultParams.amountOut - 1);
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.InsufficientAssets.selector, mockOutToken));
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

        LMPStrategy.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);

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

        LMPStrategy.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.inEthValue, 100e18);
        assertEq(stats.outEthValue, 100e18);
    }

    function test_getRebalanceValueStats_handlePositiveSlippage() public {
        // positive slippage should equal zero slippage
        defaultParams.amountOut = 100e18;
        defaultParams.amountIn = 101e18;

        LMPStrategy.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.slippage, 0);
        assertEq(stats.swapCost, 0);
    }

    function test_getRebalanceValueStats_idleOutPricesAtOneToOne() public {
        // Setting all other possibilities to something that wouldn't be 1:1
        setDestinationSpotPrice(mockOutDest, 99e16);
        setDestinationSpotPrice(mockInDest, 99e16);
        setDestinationSpotPrice(mockLMPVault, 99e16);

        uint256 outAmount = 77.7e18;

        defaultParams.tokenOut = mockBaseAsset;
        defaultParams.destinationOut = mockLMPVault;
        defaultParams.amountOut = outAmount;

        LMPStrategy.RebalanceValueStats memory stats = defaultStrat._getRebalanceValueStats(defaultParams);
        assertEq(stats.outPrice, 1e18, "outPrice");
        assertEq(stats.outEthValue, outAmount, "outEthValue");
    }

    /* **************************************** */
    /* verifyRebalanceToIdle Tests              */
    /* **************************************** */
    function test_verifyRebalanceToIdle_RevertIf_noActiveScenarioFound() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure destination is not removed from LMP

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 0);
    }

    function test_verifyRebalanceToIdle_trimOperation() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination not shutdown
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set trim to 10% of vault
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        dexStats.lstStatsData[0] = build10pctExitThresholdLst();
        setStatsCurrent(mockOutStats, dexStats);

        // set the destination to be 29% of the portfolio
        // rebalance will reduce to 24% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 2e16 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 2e16);

        defaultParams.amountOut = 250e18 - 60e18;
        defaultParams.amountIn = 50e18; // terrible exchange rate, but slippage isn't checked here
        setDestinationDebtValue(mockOutDest, 60e18, 66e18); // trim to 8.3%

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.InvalidRebalanceToIdle.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 0);
    }

    function test_verifyRebalanceToIdle_destinationShutdownSlippage() public {
        setDestinationIsShutdown(mockOutDest, true); // set destination to shutdown, 2.5% slippage
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 25e15);
    }

    function test_verifyRebalanceToIdle_lmpShutdownSlippage() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination not shutdown
        setLmpVaultIsShutdown(true); // lmp is shutdown, 1.5% slippage
        setLmpDestQueuedForRemoval(mockOutDest, false); // ensure not queued for removal

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 15e15 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 15e15);
    }

    function test_verifyRebalanceToIdle_queuedForRemovalSlippage() public {
        setDestinationIsShutdown(mockOutDest, false); // ensure destination is not shutdown
        setLmpVaultIsShutdown(false); // ensure lmp is not shutdown
        setLmpDestQueuedForRemoval(mockOutDest, true); // will return maxNormalOperationSlippage as max (1%)

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // ensure that the out destination should not be trimmed
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
        defaultStrat._verifyRebalanceToIdle(defaultParams, 1e16 + 1);

        // not expected to revert at max slippage
        defaultStrat._verifyRebalanceToIdle(defaultParams, 1e16);
    }

    function test_verifyRebalanceToIdle_picksHighestSlippage() public {
        // set all conditions to true, ex trim for simplicity
        // destinationShutdown has the highest slippage at 2.5%
        setDestinationIsShutdown(mockOutDest, true);
        setLmpVaultIsShutdown(true);
        setLmpDestQueuedForRemoval(mockOutDest, true);

        // set the destination to be 29% of the portfolio
        uint256 startingBalance = 250e18;
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;
        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // excluding trim for simplicity
        IDexLSTStats.DexLSTStatsData memory result;
        setStatsCurrent(mockOutStats, result);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.MaxSlippageExceeded.selector));
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
        LMPDebt.DestinationInfo memory info = LMPDebt.DestinationInfo({
            currentDebt: 330e18, // implied price of 1.1
            lastReport: 0, // unused
            ownedShares: 300e18, // set higher than starting balance to handle withdraw scenario
            debtBasis: 0 // unused
         });

        defaultParams.amountOut = 50e18;
        defaultParams.amountIn = 50e18;

        setLmpTotalAssets(1000e18);
        setLmpDestInfo(mockOutDest, info);
        setLmpDestinationBalanceOf(mockOutDest, startingBalance);
        setDestinationDebtValue(mockOutDest, 200e18, 220e18);

        // lmpAssetsBeforeRebalance = 1000 (assets)
        // lmpAssetsAfterRebalance = 1000 (assets) + 50 (amountIn) + 220 (destValueAfter) - 275 (destValueBefore) = 995
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
        setLmpIdle(idle);

        IStrategy.SummaryStats memory stats =
            defaultStrat._getDestinationSummaryStats(mockLMPVault, price, LMPStrategy.RebalanceDirection.In, 1);

        // only these are populated when destination is idle asset
        assertEq(stats.destination, mockLMPVault);
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
        assertEq(stats.slashingCost, 0);
    }

    function test_getDestinationSummaryStats_RevertIf_staleData() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days - 2 days - 1; // tolerance is 2 days
        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.StaleData.selector, "DexStats"));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, LMPStrategy.RebalanceDirection.Out, 0);
    }

    function test_getDestinationSummaryStats_RevertIf_reserveStatsMismatch() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        stats.lstStatsData = new ILSTStats.LSTStatsData[](2);
        stats.reservesInEth = new uint256[](1);
        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.LstStatsReservesMismatch.selector));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, LMPStrategy.RebalanceDirection.Out, 0);
    }

    function test_getDestinationSummaryStats_RevertIf_staleLstData() public {
        vm.warp(180 days);
        IDexLSTStats.DexLSTStatsData memory stats;
        stats.lastSnapshotTimestamp = 180 days;
        stats.lstStatsData = new ILSTStats.LSTStatsData[](1);
        stats.reservesInEth = new uint256[](1);
        stats.lstStatsData[0].lastSnapshotTimestamp = 180 days - 2 days - 1;

        setStatsCurrent(mockOutStats, stats);

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.StaleData.selector, "lstData"));
        defaultStrat._getDestinationSummaryStats(mockOutDest, 0, LMPStrategy.RebalanceDirection.Out, 0);
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
        setLmpDestinationBalanceOf(mockOutDest, 78e18);

        // test rebalance out
        IStrategy.SummaryStats memory summary = defaultStrat._getDestinationSummaryStats(
            mockOutDest, lpPrice, LMPStrategy.RebalanceDirection.Out, rebalanceAmount
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
        assertEq(summary.slashingCost, 0);

        // test rebalance in
        summary = defaultStrat._getDestinationSummaryStats(
            mockOutDest, lpPrice, LMPStrategy.RebalanceDirection.In, rebalanceAmount
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
        assertEq(summary.slashingCost, 0);
    }

    /* **************************************** */
    /* calculateWeightedPriceReturn Tests       */
    /* **************************************** */
    function test_calculateWeightedPriceReturn_outDiscount() public {
        int256 priceReturn = 1e17; // 10%
        uint256 reserveValue = 34e18;
        LMPStrategy.RebalanceDirection direction = LMPStrategy.RebalanceDirection.Out;

        int256 actual = defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
        // 10% * 34 * 0.75 = 2.55 (1e36)
        int256 expected = 255e34;
        assertEq(actual, expected);
    }

    function test_calculateWeightedPriceReturn_inDiscount() public {
        int256 priceReturn = 1e17; // 10%
        uint256 reserveValue = 34e18;
        LMPStrategy.RebalanceDirection direction = LMPStrategy.RebalanceDirection.In;

        int256 actual = defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
        assertEq(actual, 0);
    }

    function test_calculateWeightedPriceReturn_premium() public {
        int256 priceReturn = -1e17; // 10%
        uint256 reserveValue = 34e18;

        // same regardless of direction
        assertEq(
            defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, LMPStrategy.RebalanceDirection.In),
            -34e35
        );
        assertEq(
            defaultStrat._calculateWeightedPriceReturn(priceReturn, reserveValue, LMPStrategy.RebalanceDirection.Out),
            -34e35
        );
    }

    /* **************************************** */
    /* calculatePriceReturns Tests              */
    /* **************************************** */
    function test_calculatePriceReturns_shouldCapDiscount() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 59e15; // maxAllowed is 5e16
        dexStats.lstStatsData[0] = lstStat;

        int256[] memory priceReturns = defaultStrat._calculatePriceReturns(dexStats);
        assertEq(priceReturns.length, 1);
        assertEq(priceReturns[0], 49_999_990_354_938_271);
    }

    // Near half-life
    function test_calculatePriceReturns_shouldDecayDiscountHalf() public {
        IDexLSTStats.DexLSTStatsData memory dexStats;
        dexStats.lstStatsData = new ILSTStats.LSTStatsData[](1);

        ILSTStats.LSTStatsData memory lstStat;
        lstStat.discount = 3e16; // maxAllowed is 5e16
        vm.warp(35 days);
        uint40[5] memory discountTimestampByPercent;
        discountTimestampByPercent[0] = 1 days;
        discountTimestampByPercent[1] = 1 days;
        discountTimestampByPercent[2] = 1 days;
        discountTimestampByPercent[3] = 1 days;
        discountTimestampByPercent[4] = 1 days;
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
        uint40[5] memory discountTimestampByPercent;
        discountTimestampByPercent[0] = 1 days;
        discountTimestampByPercent[1] = 1 days;
        discountTimestampByPercent[2] = 1 days;
        discountTimestampByPercent[3] = 1 days;
        discountTimestampByPercent[4] = 1 days;
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
        uint40[5] memory discountTimestampByPercent;
        discountTimestampByPercent[0] = 1 days;
        discountTimestampByPercent[1] = 1 days;
        discountTimestampByPercent[2] = 1 days;
        discountTimestampByPercent[3] = 1 days;
        discountTimestampByPercent[4] = 1 days;
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
        uint40[5] memory discountTimestampByPercent;
        discountTimestampByPercent[0] = 1 days;
        discountTimestampByPercent[1] = 1 days;
        discountTimestampByPercent[2] = 1 days;
        discountTimestampByPercent[3] = 1 days;
        discountTimestampByPercent[4] = 1 days;
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
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.In, vm.addr(1), 1, 1);
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
        periodFinishes[0] = 180 days - 2 days + 1; // reward can be at most 2 days expired

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
        uint256 actual =
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.Out, lpToken, amount, lpPrice);
        assertEq(actual, expected);

        periodFinishes[0] = 180 days - 2 days; // make it so that even with the 2 day bump, still expired
        assertEq(
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.Out, lpToken, amount, lpPrice), 0
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
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.In, vm.addr(1), 1, 1);
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
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.In, lpToken, amount, lpPrice);
        assertEq(actual, expected);

        // test that it gets ignored if less than 7 days
        periodFinishes[0] = 180 days + 7 days - 1;
        assertEq(
            defaultStrat._calculateIncentiveApr(stat, LMPStrategy.RebalanceDirection.In, lpToken, amount, lpPrice), 0
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
        assertEq(defaultStrat.lastRebalanceTimestamp(), 1);

        // swapOffset is relaxed every 20 days in the test config
        // we want 4 relaxes to occur 20 * 4 + 1 = 81, set to 90 to ensure truncation occurs
        vm.warp(90 days);

        // each relax step is 3 days, so the expectation is 4 * 3 = 12 days
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 12 + 28);

        // init is 28 days and max is 60 days, to hit the max we need 10.67 relax periods = 213.33 days
        // exceed that to test that the swapOffset is limited to the max
        vm.warp(300 days);
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
    function test_navUpdate_RevertIf_notLMPVault() public {
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.NotLMPVault.selector));
        defaultStrat.navUpdate(100e18);
    }

    function test_navUpdate_shouldUpdateNavTracking() public {
        vm.startPrank(mockLMPVault);
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

        vm.prank(mockLMPVault);
        defaultStrat.navUpdate(10e18);

        assertFalse(defaultStrat._expiredPauseState());
    }

    function test_navUpdate_shouldPauseIfDecay() public {
        // reduced to the lookback for testing purposes only
        LMPStrategyConfig.StrategyConfig memory config = helpers.getDefaultConfig();
        config.navLookback.lookback1InDays = 1;
        config.navLookback.lookback2InDays = 2;
        config.navLookback.lookback3InDays = 3;

        LMPStrategyHarness strat = deployStrategy(config);

        vm.startPrank(mockLMPVault);
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
        LMPStrategyConfig.StrategyConfig memory config = helpers.getDefaultConfig();
        config.navLookback.lookback1InDays = 1;
        config.navLookback.lookback2InDays = 2;
        config.navLookback.lookback3InDays = 3;

        LMPStrategyHarness strat = deployStrategy(config);

        vm.startPrank(mockLMPVault);
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
    function test_rebalanceSuccessfullyExecuted_RevertIf_notLmpVault() public {
        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.NotLMPVault.selector));
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
    }

    function test_rebalanceSuccessfullyExecuted_clearsExpiredPause() public {
        // verify that it's at the init value
        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 28);

        // setup the expiredPauseState
        vm.warp(91 days);
        defaultStrat._setPausedTimestamp(1 days - 1); // must be > 0
        assertTrue(defaultStrat._expiredPauseState());

        vm.prank(mockLMPVault);
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
        vm.warp(46 days);

        vm.prank(mockLMPVault);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.swapCostOffsetPeriodInDays(), 34);
    }

    function test_rebalanceSuccessfullyExecuted_updatesLastRebalanceTimestamp() public {
        // verify it is at the initialized value
        assertEq(defaultStrat.lastRebalanceTimestamp(), 1);

        vm.warp(23 days);
        vm.prank(mockLMPVault);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.lastRebalanceTimestamp(), 23 days);
    }

    function test_rebalanceSuccessfullyExecuted_updatesDestinationLastRebalanceTimestamp() public {
        // verify it is at the initialized value
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 0);

        vm.warp(23 days);
        vm.prank(mockLMPVault);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 23 days);
    }

    function test_rebalanceSuccessfullyExecuted_updatesViolationTracking() public {
        // move the system to block.timestamp that is beyond the maxOffset
        // since timestamps are well beyond 60 days in seconds this is a OK
        // and avoids initialization scenario where a violation is tracked b/c timestamp - 0 < offset
        defaultStrat._setLastRebalanceTimestamp(60 days);
        vm.warp(60 days);

        vm.startPrank(mockLMPVault);
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

        vm.startPrank(mockLMPVault);
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

        vm.startPrank(mockLMPVault);
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

    function test_rebalanceSuccessfullyExecuted_tightenMinHandlesLargeStep() public {
        LMPStrategyConfig.StrategyConfig memory cfg = helpers.getDefaultConfig();
        cfg.swapCostOffset.minInDays = 1;
        cfg.swapCostOffset.initInDays = 2; // set below the step size
        LMPStrategyHarness testStrat = deployStrategy(cfg);

        assertEq(testStrat.swapCostOffsetTightenStepInDays(), 3);
        assertEq(testStrat.swapCostOffsetPeriodInDays(), 2);

        testStrat._setLastRebalanceTimestamp(60 days);
        vm.warp(60 days);

        vm.startPrank(mockLMPVault);
        testStrat.rebalanceSuccessfullyExecuted(defaultParams);
        assertEq(testStrat.lastAddTimestampByDestination(mockInDest), 60 days);

        // flip the direction of the rebalance
        defaultParams.destinationIn = mockOutDest;
        defaultParams.destinationOut = mockInDest;

        // generate 1 tighten; need 10 total violation tracked, we got one with the first rebal
        for (uint256 i = 1; i < 10; ++i) {
            testStrat.rebalanceSuccessfullyExecuted(defaultParams);
        }

        assertEq(testStrat.swapCostOffsetPeriodInDays(), 1);
    }

    function test_rebalanceSuccessfullyExecuted_ignoreRebalancesFromIdle() public {
        // advance so we can make sure that non-idle timestamp is updated
        vm.warp(60 days);

        ViolationTracking.State memory state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        // idle -> destination
        defaultParams.destinationOut = mockLMPVault;
        defaultParams.destinationIn = mockInDest;

        vm.startPrank(mockLMPVault);
        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);

        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        // check other direction since it skips both in/out of idle
        // destination -> idle
        defaultParams.destinationOut = mockInDest;
        defaultParams.destinationIn = mockLMPVault;

        defaultStrat.rebalanceSuccessfullyExecuted(defaultParams);
        state = defaultStrat._getViolationTrackingState();
        assertEq(state.len, 0);
        assertEq(state.violationCount, 0);

        assertEq(defaultStrat.lastAddTimestampByDestination(mockLMPVault), 0);
        assertEq(defaultStrat.lastAddTimestampByDestination(mockInDest), 60 days);
    }

    /* **************************************** */
    /* ensureNotStaleData Tests                 */
    /* **************************************** */
    function test_ensureNotStaleData_RevertIf_dataIsStale() public {
        vm.warp(90 days);
        uint256 dataTimestamp = 88 days - 1; // tolerance is 2 days

        vm.expectRevert(abi.encodeWithSelector(LMPStrategy.StaleData.selector, "data"));
        defaultStrat._ensureNotStaleData("data", dataTimestamp);
    }

    function test_ensureNotStaleData_noRevertWhenNotStale() public {
        vm.warp(90 days);
        uint256 dataTimestamp = 88 days; // tolerance is 2 days

        defaultStrat._ensureNotStaleData("data", dataTimestamp);
    }

    /* **************************************** */
    /* Test Helpers                             */
    /* **************************************** */
    function deployStrategy(LMPStrategyConfig.StrategyConfig memory cfg) internal returns (LMPStrategyHarness strat) {
        strat = new LMPStrategyHarness(ISystemRegistry(address(systemRegistry)), mockLMPVault, cfg);
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
    /* LMPVault Mocks                           */
    /* **************************************** */
    function setLmpDefaultMocks() private {
        setLmpVaultIsShutdown(false);
        setLmpVaultBaseAsset(mockBaseAsset);
        setLmpDestQueuedForRemoval(mockInDest, false);
        setLmpDestQueuedForRemoval(mockOutDest, false);
        setLmpIdle(100e18); // 100 eth
        setLmpSystemRegistry(address(systemRegistry));
        setLmpDestinationRegistered(mockInDest, true);
        setLmpDestinationRegistered(mockOutDest, true);
    }

    function setLmpVaultIsShutdown(bool shutdown) private {
        vm.mockCall(mockLMPVault, abi.encodeWithSelector(ILMPVault.isShutdown.selector), abi.encode(shutdown));
    }

    function setLmpVaultBaseAsset(address asset) private {
        vm.mockCall(mockLMPVault, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));
    }

    function setLmpDestQueuedForRemoval(address dest, bool isRemoved) private {
        vm.mockCall(
            mockLMPVault,
            abi.encodeWithSelector(ILMPVault.isDestinationQueuedForRemoval.selector, dest),
            abi.encode(isRemoved)
        );
    }

    function setLmpIdle(uint256 amount) private {
        vm.mockCall(mockLMPVault, abi.encodeWithSelector(ILMPVault.totalIdle.selector), abi.encode(amount));
    }

    function setLmpDestInfo(address dest, LMPDebt.DestinationInfo memory info) private {
        // split up in order to get around formatter issue
        bytes4 selector = ILMPVault.getDestinationInfo.selector;
        vm.mockCall(mockLMPVault, abi.encodeWithSelector(selector, dest), abi.encode(info));
    }

    function setLmpTotalAssets(uint256 amount) private {
        vm.mockCall(mockLMPVault, abi.encodeWithSelector(IERC4626.totalAssets.selector), abi.encode(amount));
    }

    function setLmpSystemRegistry(address _systemRegistry) private {
        vm.mockCall(
            mockLMPVault,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(_systemRegistry)
        );
    }

    function setLmpDestinationRegistered(address dest, bool isRegistered) private {
        vm.mockCall(
            mockLMPVault,
            abi.encodeWithSelector(ILMPVault.isDestinationRegistered.selector, dest),
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
        setLmpDestinationBalanceOf(mockInDest, 100e18);
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
        setLmpDestinationBalanceOf(mockOutDest, 100e18);
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

    function setLmpDestinationBalanceOf(address dest, uint256 amount) private {
        vm.mockCall(dest, abi.encodeWithSelector(IERC20.balanceOf.selector, address(mockLMPVault)), abi.encode(amount));
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
        setTokenPrice(mockInToken, 1e18);
        setDestinationSpotPrice(mockInDest, 1e18);
        setTokenPrice(mockInLSTToken, 1e18);
        setTokenSpotPrice(mockInLSTToken, 1e18);
        setTokenDecimals(mockInToken, 18);
        setTokenPrice(mockOutToken, 1e18);
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

contract LMPStrategyHarness is LMPStrategy {
    constructor(
        ISystemRegistry _systemRegistry,
        address _lmpVault,
        LMPStrategyConfig.StrategyConfig memory conf
    ) LMPStrategy(_systemRegistry, _lmpVault, conf) { }

    function _validateRebalanceParams(IStrategy.RebalanceParams memory params) public view {
        validateRebalanceParams(params);
    }

    function _getRebalanceValueStats(IStrategy.RebalanceParams memory params)
        public
        returns (RebalanceValueStats memory)
    {
        return getRebalanceValueStats(params);
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
        return calculatePriceReturns(stats);
    }

    function _calculateIncentiveApr(
        IDexLSTStats.StakingIncentiveStats memory stats,
        RebalanceDirection direction,
        address destAddress,
        uint256 amount,
        uint256 price
    ) public view returns (uint256) {
        return calculateIncentiveApr(stats, direction, destAddress, amount, price);
    }

    function _getIncentivePrice(IIncentivesPricingStats pricing, address token) public view returns (uint256) {
        return getIncentivePrice(pricing, token);
    }

    function _getDestinationSummaryStats(
        address destAddress,
        uint256 price,
        RebalanceDirection direction,
        uint256 amount
    ) public returns (IStrategy.SummaryStats memory) {
        return getDestinationSummaryStats(destAddress, price, direction, amount);
    }

    function _calculateWeightedPriceReturn(
        int256 priceReturn,
        uint256 reserveValue,
        RebalanceDirection direction
    ) public view returns (int256) {
        return calculateWeightedPriceReturn(priceReturn, reserveValue, direction);
    }
}
