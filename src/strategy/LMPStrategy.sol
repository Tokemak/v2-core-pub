// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { Errors } from "src/utils/Errors.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ViolationTracking } from "src/strategy/ViolationTracking.sol";
import { NavTracking } from "src/strategy/NavTracking.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
// TODO: how do we ensure that we don't have dust positions -- require min positions on rebalance
// TODO: confirm the order that verification occurs vs the actual creation/burning of LP tokens from rebalances

contract LMPStrategy is ILMPStrategy, SecurityBase {
    using ViolationTracking for ViolationTracking.State;
    using NavTracking for NavTracking.State;
    using SubSaturateMath for uint256;
    using SubSaturateMath for int256;
    using Math for uint256;

    // when removing liquidity, rewards can be expired by this amount if the pool as incentive credits
    uint256 private constant EXPIRED_REWARD_TOLERANCE = 2 days;

    /* ******************************** */
    /* Immutable Config                 */
    /* ******************************** */
    /// @notice Tokemak system-level registry. Used to lookup other services (e.g., pricing)
    ISystemRegistry public immutable systemRegistry;

    /// @notice The LMPVault that this strategy is associated with
    ILMPVaultForStrategy public immutable lmpVault;

    /// @notice the number of days to pause rebalancing due to NAV decay
    uint16 public immutable pauseRebalancePeriodInDays;

    /// @notice destinations trading a premium above maxPremium will be blocked from new capital deployments
    int256 public immutable maxPremium; // 100% = 1e18

    /// @notice destinations trading a discount above maxDiscount will be blocked from new capital deployments
    int256 public immutable maxDiscount; // 100% = 1e18

    /// @notice the allowed staleness of stats data before a revert occurs
    uint40 public immutable staleDataToleranceInSeconds;

    /// @notice the swap cost offset period to initialize the strategy with
    uint16 public immutable swapCostOffsetInitInDays;

    /// @notice the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
    uint16 public immutable swapCostOffsetTightenThresholdInViolations;

    /// @notice the number of days to decrease the swap offset period for each tightening step
    uint16 public immutable swapCostOffsetTightenStepInDays;

    /// @notice the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
    uint16 public immutable swapCostOffsetRelaxThresholdInDays;

    /// @notice the number of days to increase the swap offset period for each relaxing step
    uint16 public immutable swapCostOffsetRelaxStepInDays;

    // slither-disable-start similar-names
    /// @notice the maximum the swap cost offset period can reach. This is the loosest the strategy will be
    uint16 public immutable swapCostOffsetMaxInDays;

    /// @notice the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
    uint16 public immutable swapCostOffsetMinInDays;

    /// @notice the number of days for the first NAV decay comparison (e.g., 30 days)
    uint8 public immutable navLookback1InDays;

    /// @notice the number of days for the second NAV decay comparison (e.g., 60 days)
    uint8 public immutable navLookback2InDays;

    /// @notice the number of days for the third NAV decay comparison (e.g., 90 days)
    uint8 public immutable navLookback3InDays;
    // slither-disable-end similar-names

    /// @notice the maximum slippage that is allowed for a normal rebalance
    uint256 public immutable maxNormalOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxTrimOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destinationVault has been shutdown
    /// shutdown for a vault is abnormal and means there is an issue at that destination
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxEmergencyOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when the LMPVault has been shutdown
    uint256 public immutable maxShutdownOperationSlippage; // 100% = 1e18

    /// @notice the maximum discount used for price return
    int256 public immutable maxAllowedDiscount; // 18 precision

    /// @notice model weight used for LSTs base yield, 1e6 is the highest
    uint256 public immutable weightBase;

    /// @notice model weight used for DEX fee yield, 1e6 is the highest
    uint256 public immutable weightFee;

    /// @notice model weight used for incentive yield
    uint256 public immutable weightIncentive;

    /// @notice model weight used slashing costs
    uint256 public immutable weightSlashing;

    /// @notice model weight applied to an LST discount when exiting the position
    int256 public immutable weightPriceDiscountExit;

    /// @notice model weight applied to an LST discount when entering the position
    int256 public immutable weightPriceDiscountEnter;

    /// @notice model weight applied to an LST premium when entering or exiting the position
    int256 public immutable weightPricePremium;

    /// @notice model weight applied to an LST premium when entering or exiting the position
    uint256 public immutable lstPriceGapTolerance;

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */
    /// @notice The timestamp for when rebalancing was last paused
    uint40 public lastPausedTimestamp;

    /// @notice The last timestamp that a destination was added to
    mapping(address => uint40) public lastAddTimestampByDestination;

    /// @notice The last timestamp a rebalance was completed
    uint40 public lastRebalanceTimestamp;

    /// @notice Rebalance violation tracking state
    ViolationTracking.State public violationTrackingState;

    /// @notice NAV tracking state
    NavTracking.State public navTrackingState;

    uint16 private _swapCostOffsetPeriod;

    /* ******************************** */
    /* Events                           */
    /* ******************************** */
    event RebalanceComplete();

    /* ******************************** */
    /* Errors                           */
    /* ******************************** */
    error NotLMPVault();
    error StrategyPaused();
    error RebalanceDestinationsMatch();
    error RebalanceDestinationUnderlyerMismatch(address destination, address trueUnderlyer, address providedUnderlyer);
    error LstStatsReservesMismatch();
    error StaleData(string name);
    error SwapCostExceeded();
    error MaxSlippageExceeded();
    error MaxDiscountExceeded();
    error MaxPremiumExceeded();
    error OnlyRebalanceToIdleAvailable();
    error InvalidRebalanceToIdle();
    error CannotConvertUintToInt();
    error InsufficientAssets(address asset);
    error SystemRegistryMismatch();
    error UnregisteredDestination(address dest);
    error LSTPriceGapToleranceExceeded();

    struct SummaryStats {
        address destination;
        uint256 baseApr;
        uint256 feeApr;
        uint256 incentiveApr;
        uint256 safeTotalSupply;
        int256 priceReturn;
        int256 maxDiscount;
        int256 maxPremium;
        uint256 ownedShares;
        int256 compositeReturn;
        uint256 pricePerShare;
        uint256 slashingCost;
    }

    struct InterimStats {
        uint256 baseApr;
        int256 priceReturn;
        int256 maxDiscount;
        int256 maxPremium;
    }

    struct RebalanceValueStats {
        uint256 inPrice;
        uint256 outPrice;
        uint256 inEthValue;
        uint256 outEthValue;
        uint256 swapCost;
        uint256 slippage;
    }

    enum RebalanceDirection {
        In,
        Out
    }

    modifier onlyLMPVault() {
        if (msg.sender != address(lmpVault)) revert NotLMPVault();
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _lmpVault,
        LMPStrategyConfig.StrategyConfig memory conf
    ) SecurityBase(address(_systemRegistry.accessController())) {
        systemRegistry = _systemRegistry;
        Errors.verifyNotZero(_lmpVault, "_lmpVault");

        if (ISystemComponent(_lmpVault).getSystemRegistry() != address(_systemRegistry)) {
            revert SystemRegistryMismatch();
        }

        lmpVault = ILMPVaultForStrategy(_lmpVault);

        LMPStrategyConfig.validate(conf);

        pauseRebalancePeriodInDays = conf.pauseRebalancePeriodInDays;
        maxPremium = conf.maxPremium;
        maxDiscount = conf.maxDiscount;
        staleDataToleranceInSeconds = conf.staleDataToleranceInSeconds;
        swapCostOffsetInitInDays = conf.swapCostOffset.initInDays;
        swapCostOffsetTightenThresholdInViolations = conf.swapCostOffset.tightenThresholdInViolations;
        swapCostOffsetTightenStepInDays = conf.swapCostOffset.tightenStepInDays;
        swapCostOffsetRelaxThresholdInDays = conf.swapCostOffset.relaxThresholdInDays;
        swapCostOffsetRelaxStepInDays = conf.swapCostOffset.relaxStepInDays;
        swapCostOffsetMaxInDays = conf.swapCostOffset.maxInDays;
        swapCostOffsetMinInDays = conf.swapCostOffset.minInDays;
        navLookback1InDays = conf.navLookback.lookback1InDays;
        navLookback2InDays = conf.navLookback.lookback2InDays;
        navLookback3InDays = conf.navLookback.lookback3InDays;
        maxNormalOperationSlippage = conf.slippage.maxNormalOperationSlippage;
        maxTrimOperationSlippage = conf.slippage.maxTrimOperationSlippage;
        maxEmergencyOperationSlippage = conf.slippage.maxEmergencyOperationSlippage;
        maxShutdownOperationSlippage = conf.slippage.maxShutdownOperationSlippage;
        maxAllowedDiscount = conf.maxAllowedDiscount;
        weightBase = conf.modelWeights.baseYield;
        weightFee = conf.modelWeights.feeYield;
        weightIncentive = conf.modelWeights.incentiveYield;
        weightSlashing = conf.modelWeights.slashing;
        weightPriceDiscountExit = conf.modelWeights.priceDiscountExit;
        weightPriceDiscountEnter = conf.modelWeights.priceDiscountEnter;
        weightPricePremium = conf.modelWeights.pricePremium;
        lstPriceGapTolerance = conf.lstPriceGapTolerance;

        _swapCostOffsetPeriod = conf.swapCostOffset.initInDays;
        lastRebalanceTimestamp = uint40(block.timestamp);
    }

    /// @inheritdoc ILMPStrategy
    function verifyRebalance(IStrategy.RebalanceParams memory params)
        public
        returns (bool success, string memory message)
    {
        validateRebalanceParams(params);

        RebalanceValueStats memory valueStats = getRebalanceValueStats(params);

        // moves from a destination back to eth only happen under specific scenarios
        // if the move is valid, the constraints are different than if assets are moving to a normal destination
        if (params.destinationIn == address(lmpVault)) {
            verifyRebalanceToIdle(params, valueStats.slippage);
            // exit early b/c the remaining constraints only apply when moving to a normal destination
            return (true, "");
        }

        // rebalances back to idle are allowed even when a strategy is paused
        // all other rebalances should be blocked in a paused state
        ensureNotPaused();
        // Verify spot & safe price for the individual tokens in the pool are not far apart.
        if (!verifyLSTPriceGap(params, lstPriceGapTolerance)) revert LSTPriceGapToleranceExceeded();

        // ensure that we're not exceeding top-level max slippage
        if (valueStats.slippage > maxNormalOperationSlippage) revert MaxSlippageExceeded();

        (SummaryStats memory outSummary, SummaryStats memory inSummary) = getRebalanceSummaryStats(params, valueStats);

        // ensure that the destination that is being added to doesn't exceed top-level premium/discount constraints
        if (inSummary.maxDiscount > maxDiscount) revert MaxDiscountExceeded();
        if (-inSummary.maxPremium > maxPremium) revert MaxPremiumExceeded();

        uint256 swapOffsetPeriod = swapCostOffsetPeriodInDays();

        // if the swap is only moving lp tokens from one destination to another
        // make the swap offset period more conservative b/c the gas costs/complexity is lower
        if (params.tokenIn == params.tokenOut) {
            swapOffsetPeriod = swapOffsetPeriod / 2; // TODO: this should be configurable
        }

        // slither-disable-start divide-before-multiply
        // equation is `compositeReturn * ethValue` / 1e18, which is multiply before divide
        // compositeReturn and ethValue are both 1e18 precision
        int256 predictedAnnualizedGain = (inSummary.compositeReturn * convertUintToInt(valueStats.inEthValue))
            .subSaturate(outSummary.compositeReturn * convertUintToInt(valueStats.outEthValue)) / 1e18;

        // slither-disable-end divide-before-multiply
        int256 predictedGainAtOffsetEnd = (predictedAnnualizedGain * convertUintToInt(swapOffsetPeriod) / 365);

        // if the predicted gain in Eth by the end of the swap offset period is less than
        // the swap cost then revert b/c the vault will not offset slippage in sufficient time
        // slither-disable-next-line timestamp
        if (predictedGainAtOffsetEnd <= convertUintToInt(valueStats.swapCost)) revert SwapCostExceeded();

        // TODO: make it return nothing b/c the absence of a revert is what we're looking for
        return (true, "");
    }

    // TODO: must validate that we have valid destinations for the LMP
    function validateRebalanceParams(IStrategy.RebalanceParams memory params) internal view {
        Errors.verifyNotZero(params.destinationIn, "destinationIn");
        Errors.verifyNotZero(params.destinationOut, "destinationOut");
        Errors.verifyNotZero(params.tokenIn, "tokenIn");
        Errors.verifyNotZero(params.tokenOut, "tokenOut");
        Errors.verifyNotZero(params.amountIn, "amountIn");
        Errors.verifyNotZero(params.amountOut, "amountOut");

        ensureDestinationRegistered(params.destinationIn);
        ensureDestinationRegistered(params.destinationOut);

        // when a vault is shutdown, rebalancing can only pull assets from destinations back to the vault
        if (lmpVault.isShutdown() && params.destinationIn != address(lmpVault)) revert OnlyRebalanceToIdleAvailable();

        if (params.destinationIn == params.destinationOut) revert RebalanceDestinationsMatch();

        address baseAsset = lmpVault.asset();

        // if the in/out destination is the LMPVault then the in/out token must be the baseAsset
        // if the in/out is not the LMPVault then the in/out token must match the destinations underlying token
        if (params.destinationIn == address(lmpVault)) {
            if (params.tokenIn != baseAsset) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationIn, params.tokenIn, baseAsset);
            }
        } else {
            IDestinationVaultForStrategy inDest = IDestinationVaultForStrategy(params.destinationIn);
            if (params.tokenIn != inDest.underlying()) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationIn, inDest.underlying(), params.tokenIn);
            }
        }

        if (params.destinationOut == address(lmpVault)) {
            if (params.tokenOut != baseAsset) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationOut, params.tokenOut, baseAsset);
            }
            if (params.amountOut > lmpVault.totalIdle()) {
                revert InsufficientAssets(params.tokenOut);
            }
        } else {
            IDestinationVaultForStrategy outDest = IDestinationVaultForStrategy(params.destinationOut);
            if (params.tokenOut != outDest.underlying()) {
                revert RebalanceDestinationUnderlyerMismatch(
                    params.destinationOut, outDest.underlying(), params.tokenOut
                );
            }
            if (params.amountOut > outDest.balanceOf(address(lmpVault))) {
                revert InsufficientAssets(params.tokenOut);
            }
        }
    }

    function ensureDestinationRegistered(address dest) private view {
        if (dest == address(lmpVault)) return;
        if (!(lmpVault.isDestinationRegistered(dest) || lmpVault.isDestinationQueuedForRemoval(dest))) {
            revert UnregisteredDestination(dest);
        }
    }

    function getRebalanceValueStats(IStrategy.RebalanceParams memory params)
        internal
        returns (RebalanceValueStats memory)
    {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        uint256 outPrice = pricer.getPriceInEth(params.tokenOut);
        uint256 inPrice = pricer.getPriceInEth(params.tokenIn);

        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();

        // prices are 1e18 and we want values in 1e18, so divide by token decimals
        uint256 outEthValue = outPrice * params.amountOut / 10 ** tokenOutDecimals;

        // amountIn is a minimum to receive, but it is OK if we receive more
        uint256 inEthValue = inPrice * params.amountIn / 10 ** tokenInDecimals;

        uint256 swapCost = outEthValue.subSaturate(inEthValue);
        uint256 slippage = swapCost * 1e18 / outEthValue;

        return RebalanceValueStats({
            inPrice: inPrice,
            outPrice: outPrice,
            inEthValue: inEthValue,
            outEthValue: outEthValue,
            swapCost: swapCost,
            slippage: slippage
        });
    }

    // Calculate the largest difference between spot & safe price for the underlying LST tokens.
    // This does not support Curve meta pools
    function verifyLSTPriceGap(IStrategy.RebalanceParams memory params, uint256 tolerance) internal returns (bool) {
        // Pricer
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        // Out Destination
        IDestinationVaultForStrategy dest = IDestinationVaultForStrategy(params.destinationOut);
        address[] memory lstTokens = dest.underlyingTokens();
        uint256 numLsts = lstTokens.length;
        for (uint256 i = 0; i < numLsts; ++i) {
            uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
            uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], params.tokenOut);
            // For out destination, the pool tokens should not be lower than safe price by tolerance
            if (priceSafe > priceSpot) {
                if (((priceSafe * 1.0e18 / priceSpot - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                    return false;
                }
            }
        }

        // In Destination
        dest = IDestinationVaultForStrategy(params.destinationIn);
        lstTokens = dest.underlyingTokens();
        numLsts = lstTokens.length;
        for (uint256 i = 0; i < numLsts; ++i) {
            uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
            uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], params.tokenIn);
            // For in destination, the pool tokens should not be higher than safe price by tolerance
            if (priceSpot > priceSafe) {
                if (((priceSpot * 1.0e18 / priceSafe - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                    return false;
                }
            }
        }

        return true;
    }

    // TODO: perhaps we should just have a set order to the checks to push expensive operations out
    // or have the solver tell us why we're moving back to idle
    function verifyRebalanceToIdle(IStrategy.RebalanceParams memory params, uint256 slippage) internal {
        IDestinationVaultForStrategy outDest = IDestinationVaultForStrategy(params.destinationOut);

        // multiple scenarios can be active at a given time. We want to use the highest
        // slippage among the active scenarios.
        uint256 maxSlippage = 0;

        // Scenario 1: the destination has been shutdown -- done when a fast exit is required
        if (outDest.isShutdown()) {
            maxSlippage = maxEmergencyOperationSlippage;
        }

        // Scenario 2: the LMPVault has been shutdown
        if (lmpVault.isShutdown() && maxShutdownOperationSlippage > maxSlippage) {
            maxSlippage = maxShutdownOperationSlippage;
        }

        // Scenario 3: the destination has been moved out of the LMPs active destinations
        if (lmpVault.isDestinationQueuedForRemoval(params.destinationOut) && maxNormalOperationSlippage > maxSlippage) {
            maxSlippage = maxNormalOperationSlippage;
        }

        // Scenario 4: the destination needs to be trimmed because it violated a constraint
        if (maxTrimOperationSlippage > maxSlippage) {
            uint256 trimAmount = getDestinationTrimAmount(outDest); // this is expensive, can it be refactored?
            if (trimAmount < 1e18 && verifyTrimOperation(params, trimAmount)) {
                maxSlippage = maxTrimOperationSlippage;
            }
        }

        // if none of the scenarios are active then this rebalance is invalid
        if (maxSlippage == 0) revert InvalidRebalanceToIdle();

        if (slippage > maxSlippage) revert MaxSlippageExceeded();
    }

    function verifyTrimOperation(IStrategy.RebalanceParams memory params, uint256 trimAmount) internal returns (bool) {
        // if the position can be trimmed to zero, then no checks are necessary
        if (trimAmount == 0) {
            return true;
        }

        IDestinationVaultForStrategy outDest = IDestinationVaultForStrategy(params.destinationOut);

        // TODO: revert if information is too old?
        LMPDebt.DestinationInfo memory destInfo = lmpVault.getDestinationInfo(params.destinationOut);

        // shares of the destination currently held by the LMPVault
        uint256 currentShares = outDest.balanceOf(address(lmpVault));

        // withdrawals reduce totalAssets, but do not update the destinationInfo
        // adjust the current debt based on the currently owned shares
        // TODO: triple check that currentShares <= destInfo.ownedShares (always)
        uint256 currentDebt = destInfo.currentDebt * currentShares / destInfo.ownedShares;

        // prior validation ensures that currentShares >= amountOut
        uint256 sharesAfterRebalance = currentShares - params.amountOut;

        // TODO: does the removal of the assets from the destination have a known price impact?
        // TODO: consider a check after the rebalance is complete that checks the portfolio value is as expected
        // current value of the destination shares, not cached from debt reporting
        uint256 destValueAfterRebalance = outDest.debtValue(sharesAfterRebalance);

        // calculate the total value of the lmpVault after the rebalance is made
        // note that only the out destination value is adjusted to current
        // amountIn is a minimum to receive, but it is OK if we receive more
        uint256 lmpAssetsAfterRebalance =
            (lmpVault.totalAssets() + params.amountIn + destValueAfterRebalance - currentDebt);

        // trimming may occur over multiple rebalances, so we only want to ensure we aren't removing too much
        return destValueAfterRebalance * 1e18 / lmpAssetsAfterRebalance >= trimAmount;
    }

    // TODO: it is confusing that it returns 100% for no trim
    function getDestinationTrimAmount(IDestinationVaultForStrategy dest) internal returns (uint256) {
        uint256 discountThreshold = 3e5; // 3% 1e7 precision, discount required to consider trimming
        uint256 discountDaysThreshold = 7; // number of last 10 days that it was >= discountThreshold
        int256 exitDiscountThreshold = 5e16; // 5% 1e18 precision, discount required to completely exit

        // this is always the out destination and guaranteed not to be the LMPVault idle asset
        IDexLSTStats.DexLSTStatsData memory stats = dest.getStats().current();

        ILSTStats.LSTStatsData[] memory lstStats = stats.lstStatsData;
        uint256 numLsts = lstStats.length;

        uint256 minTrim = 1e18; // 100% -- no trim required
        for (uint256 i = 0; i < numLsts; ++i) {
            ILSTStats.LSTStatsData memory targetLst = lstStats[i];
            uint256 numDiscountOverThreshold = getDiscountAboveThreshold(targetLst.discountHistory, discountThreshold);

            if (targetLst.discount >= exitDiscountThreshold && numDiscountOverThreshold >= discountDaysThreshold) {
                // this is the worst possible trim, so we can exit without checking other LSTs
                return 0;
            }

            // discountThreshold is 1e7 precision for the discount history, but here it is compared to a 1e18, so pad it
            if (
                targetLst.discount >= int256(discountThreshold * 1e11)
                    && numDiscountOverThreshold >= discountDaysThreshold
            ) {
                minTrim = minTrim.min(1e17); // 10%
            }
        }

        return minTrim;
    }

    function getDiscountAboveThreshold(
        uint24[10] memory discountHistory,
        uint256 threshold
    ) internal pure returns (uint256 count) {
        count = 0;
        uint256 len = discountHistory.length;
        for (uint256 i = 0; i < len; ++i) {
            if (discountHistory[i] >= threshold) {
                count += 1;
            }
        }
    }

    function getRebalanceSummaryStats(
        IStrategy.RebalanceParams memory params,
        RebalanceValueStats memory valueStats
    ) internal returns (SummaryStats memory outSummary, SummaryStats memory inSummary) {
        outSummary = getDestinationSummaryStats(
            params.destinationOut, valueStats.outPrice, RebalanceDirection.Out, params.amountOut
        );

        inSummary = (
            getDestinationSummaryStats(params.destinationIn, valueStats.inPrice, RebalanceDirection.In, params.amountIn)
        );
    }

    function getDestinationSummaryStats(
        address destAddress,
        uint256 price,
        RebalanceDirection direction,
        uint256 amount
    ) internal returns (SummaryStats memory) {
        // NOTE: creating this as empty to save on variables later
        // has the distinct downside that if you forget to update a value, you get the zero value
        // slither-disable-next-line uninitialized-local
        SummaryStats memory result;

        if (destAddress == address(lmpVault)) {
            result.destination = destAddress;
            result.ownedShares = lmpVault.totalIdle();
            result.pricePerShare = price;
            return result;
        }

        IDestinationVaultForStrategy dest = IDestinationVaultForStrategy(destAddress);
        IDexLSTStats.DexLSTStatsData memory stats = dest.getStats().current();

        ensureNotStaleData("DexStats", stats.lastSnapshotTimestamp);

        uint256 numLstStats = stats.lstStatsData.length;
        if (numLstStats != stats.reservesInEth.length) revert LstStatsReservesMismatch();

        // TODO: move this into the loop to avoid iterating the LSTs 2x
        int256[] memory priceReturns = calculatePriceReturns(stats);

        // temporary holder to reduce variables
        InterimStats memory interimStats;

        // TODO: estimate reserves for this calculation; or change the underlying stats
        uint256 reservesTotal = 0;
        for (uint256 i = 0; i < numLstStats; ++i) {
            ensureNotStaleData("lstData", stats.lstStatsData[i].lastSnapshotTimestamp);

            uint256 reserveValue = stats.reservesInEth[i];
            reservesTotal += reserveValue;

            interimStats.baseApr += stats.lstStatsData[i].baseApr * reserveValue;
            interimStats.priceReturn += calculateWeightedPriceReturn(priceReturns[i], reserveValue, direction);

            int256 discount = stats.lstStatsData[i].discount;
            // slither-disable-next-line timestamp
            if (discount < interimStats.maxPremium) {
                interimStats.maxPremium = discount;
            }
            // slither-disable-next-line timestamp
            if (discount > interimStats.maxDiscount) {
                interimStats.maxDiscount = discount;
            }
        }

        // if reserves are 0, then leave baseApr + priceReturn as 0
        if (reservesTotal > 0) {
            result.baseApr = interimStats.baseApr / reservesTotal;
            result.priceReturn = interimStats.priceReturn / convertUintToInt(reservesTotal);
        }

        result.destination = destAddress;
        result.feeApr = stats.feeApr;
        result.incentiveApr = calculateIncentiveApr(stats.stakingIncentiveStats, direction, destAddress, amount, price);
        result.safeTotalSupply = stats.stakingIncentiveStats.safeTotalSupply;
        result.ownedShares = dest.balanceOf(address(lmpVault));
        result.pricePerShare = price;
        result.maxPremium = interimStats.maxPremium;
        result.maxDiscount = interimStats.maxDiscount;

        uint256 returnExPrice = (
            result.baseApr * weightBase / 1e6 + result.feeApr * weightFee / 1e6
                + result.incentiveApr * weightIncentive / 1e6
        );

        result.compositeReturn = convertUintToInt(returnExPrice) + result.priceReturn; // price already weighted

        return result;
    }

    function calculateWeightedPriceReturn(
        int256 priceReturn,
        uint256 reserveValue,
        RebalanceDirection direction
    ) internal view returns (int256) {
        if (priceReturn > 0) {
            // LST trading at a discount
            if (direction == RebalanceDirection.Out) {
                return priceReturn * convertUintToInt(reserveValue) * weightPriceDiscountExit / 1e6;
            } else {
                return priceReturn * convertUintToInt(reserveValue) * weightPriceDiscountEnter / 1e6;
            }
        } else {
            // LST trading at 0 or a premium
            return priceReturn * convertUintToInt(reserveValue) * weightPricePremium / 1e6;
        }
    }

    // TODO: how are tokemak-level rewards accounted for?
    function calculateIncentiveApr(
        IDexLSTStats.StakingIncentiveStats memory stats,
        RebalanceDirection direction,
        address destAddress,
        uint256 lpAmountToAddOrRemove,
        uint256 lpPrice
    ) internal view returns (uint256) {
        IIncentivesPricingStats pricing = systemRegistry.incentivePricing();

        bool hasCredits = stats.incentiveCredits > 0;
        uint256 totalRewards = 0;

        uint256 numRewards = stats.annualizedRewardAmounts.length;
        for (uint256 i = 0; i < numRewards; ++i) {
            address rewardToken = stats.rewardTokens[i];
            uint256 tokenPrice = getIncentivePrice(pricing, rewardToken);

            // skip processing if the token is worthless or unregistered
            if (tokenPrice == 0) continue;

            uint256 periodFinish = stats.periodFinishForRewards[i];
            uint256 rewardRate = stats.annualizedRewardAmounts[i];
            uint256 rewardDivisor = 10 ** IERC20Metadata(rewardToken).decimals();

            if (direction == RebalanceDirection.Out) {
                // if the destination has credits then extend the periodFinish by the expiredTolerance
                // this allows destinations that consistently had rewards some leniency
                if (hasCredits) {
                    periodFinish += EXPIRED_REWARD_TOLERANCE;
                }

                // slither-disable-next-line timestamp
                if (periodFinish > block.timestamp) {
                    // tokenPrice is 1e18 and we want 1e18 out, so divide by the token decimals
                    totalRewards += rewardRate * tokenPrice / rewardDivisor;
                }
            } else {
                // when adding to a destination, count incentives only when either of the following conditions are met:
                // 1) the incentive lasts at least 7 days
                // 2) the incentive lasts >3 days and the destination has a positive incentive credit balance
                if (
                    // slither-disable-next-line timestamp
                    periodFinish >= block.timestamp + 7 days || (hasCredits && periodFinish > block.timestamp + 3 days)
                ) {
                    // tokenPrice is 1e18 and we want 1e18 out, so divide by the token decimals
                    totalRewards += rewardRate * tokenPrice / rewardDivisor;
                }
            }
        }

        if (totalRewards == 0) {
            return 0;
        }

        uint256 lpTokenDivisor = 10 ** IDestinationVaultForStrategy(destAddress).decimals();
        uint256 totalSupplyInEth = 0;
        if (direction == RebalanceDirection.Out) {
            totalSupplyInEth = stats.safeTotalSupply.subSaturate(lpAmountToAddOrRemove) * lpPrice / lpTokenDivisor;
        } else {
            totalSupplyInEth = (stats.safeTotalSupply + lpAmountToAddOrRemove) * lpPrice / lpTokenDivisor;
        }

        // TODO: what if the denominator is zero?
        return (totalRewards * 1e18) / totalSupplyInEth;
    }

    function getIncentivePrice(IIncentivesPricingStats pricing, address token) internal view returns (uint256) {
        (uint256 fastPrice, uint256 slowPrice) = pricing.getPriceOrZero(token, staleDataToleranceInSeconds);
        return fastPrice.min(slowPrice);
    }

    function calculatePriceReturns(IDexLSTStats.DexLSTStatsData memory stats) internal view returns (int256[] memory) {
        ILSTStats.LSTStatsData[] memory lstStatsData = stats.lstStatsData;

        // TODO: pretty sure we need to look at the actual destination-level prices, not use the oracle variant
        uint256 numLsts = lstStatsData.length;
        int256[] memory priceReturns = new int256[](numLsts);

        for (uint256 i = 0; i < numLsts; ++i) {
            ILSTStats.LSTStatsData memory data = lstStatsData[i];

            int256 scalingFactor = 1e18; // default scalingFactor is 1

            int256 discount = data.discount;
            if (discount > maxAllowedDiscount) {
                discount = maxAllowedDiscount;
            }

            // TODO: insert actual logic

            priceReturns[i] = discount * scalingFactor / 1e18;
        }

        return priceReturns;
    }

    /// @inheritdoc ILMPStrategy
    function navUpdate(uint256 navPerShare) external onlyLMPVault {
        uint40 blockTime = uint40(block.timestamp);
        navTrackingState.insert(navPerShare, blockTime);

        clearExpiredPause();

        // check if the strategy needs to be paused due to NAV decay
        // the check only happens after there are enough data points
        // skip the check if the strategy is already paused
        // slither-disable-next-line timestamp
        if (navTrackingState.len > navLookback3InDays && !paused()) {
            uint256 nav1 = navTrackingState.getDaysAgo(navLookback1InDays);
            uint256 nav2 = navTrackingState.getDaysAgo(navLookback2InDays);
            uint256 nav3 = navTrackingState.getDaysAgo(navLookback3InDays);

            if (navPerShare < nav1 && navPerShare < nav2 && navPerShare < nav3) {
                lastPausedTimestamp = blockTime;
            }
        }
    }

    /// @inheritdoc ILMPStrategy
    function rebalanceSuccessfullyExecuted(IStrategy.RebalanceParams memory params) external onlyLMPVault {
        // clearExpirePause sets _swapCostOffsetPeriod, so skip when possible to avoid double write
        if (!clearExpiredPause()) _swapCostOffsetPeriod = swapCostOffsetPeriodInDays();

        // TODO: is it ok to set this on any rebalance, including in/out from idle
        // probably want to exclude rebalances to idle since those skip swapCostOffset logic
        lastRebalanceTimestamp = uint40(block.timestamp);

        address lmpAddress = address(lmpVault);

        // update the destination that had assets added
        // moves into idle are not tracked for violations
        if (params.destinationIn != lmpAddress) {
            lastAddTimestampByDestination[params.destinationIn] = lastRebalanceTimestamp;
        }

        // violations are only tracked when moving between non-idle assets
        if (params.destinationOut != lmpAddress && params.destinationIn != lmpAddress) {
            uint40 lastAddForRemoveDestination = lastAddTimestampByDestination[params.destinationOut];
            if (
                // slither-disable-start timestamp
                lastRebalanceTimestamp - lastAddForRemoveDestination < uint40(swapCostOffsetPeriodInDays()) * 1 days
            ) {
                // slither-disable-end timestamp

                violationTrackingState.insert(true);
            } else {
                violationTrackingState.insert(false);
            }
        }

        // tighten if X of the last 10 rebalances were violations
        if (
            violationTrackingState.len == 10
                && violationTrackingState.violationCount >= swapCostOffsetTightenThresholdInViolations
        ) {
            tightenSwapCostOffset();
            violationTrackingState.reset();
        }

        // move the destination decreased to the head and the destination increased to the tail of the withdrawal queue
        // don't add Idle ETH to either the head or the tail of the withdrawal queue
        if (params.destinationOut != address(lmpVault)) {
            ILMPVaultForStrategy(lmpVault).addToWithdrawalQueueHead(params.destinationOut);
        }
        if (params.destinationIn != address(lmpVault)) {
            ILMPVaultForStrategy(lmpVault).addToWithdrawalQueueTail(params.destinationIn);
        }
    }

    function swapCostOffsetPeriodInDays() public view returns (uint16) {
        // if the system is in an expired pause state then ensure that swap cost offset
        // is set to the most conservative value (shortest number of days)
        if (expiredPauseState()) {
            return swapCostOffsetMinInDays;
        }

        // truncation is desirable because we only want the number of times it has exceeded the threshold
        // slither-disable-next-line divide-before-multiply
        uint40 numRelaxPeriods =
            (uint40(block.timestamp) - lastRebalanceTimestamp) / 1 days / uint40(swapCostOffsetRelaxThresholdInDays);
        uint40 relaxDays = numRelaxPeriods * uint40(swapCostOffsetRelaxStepInDays);
        uint40 newSwapCostOffset = uint40(_swapCostOffsetPeriod) + relaxDays;

        // slither-disable-next-line timestamp
        if (newSwapCostOffset > swapCostOffsetMaxInDays) {
            return swapCostOffsetMaxInDays;
        }

        return uint16(newSwapCostOffset);
    }

    function tightenSwapCostOffset() internal {
        uint16 currentSwapOffset = swapCostOffsetPeriodInDays();
        uint16 newSwapCostOffset = 0;

        if (currentSwapOffset > swapCostOffsetTightenStepInDays) {
            newSwapCostOffset = currentSwapOffset - swapCostOffsetTightenStepInDays;
        }

        // slither-disable-next-line timestamp
        if (newSwapCostOffset < swapCostOffsetMinInDays) {
            _swapCostOffsetPeriod = swapCostOffsetMinInDays;
        } else {
            _swapCostOffsetPeriod = newSwapCostOffset;
        }
    }

    function paused() public view returns (bool) {
        // slither-disable-next-line incorrect-equality,timestamp
        if (lastPausedTimestamp == 0) return false;
        uint40 pauseRebalanceInSeconds = uint40(pauseRebalancePeriodInDays) * 1 days;

        // slither-disable-next-line timestamp
        return uint40(block.timestamp) - lastPausedTimestamp <= pauseRebalanceInSeconds;
    }

    function ensureNotPaused() internal view {
        if (paused()) revert StrategyPaused();
    }

    function expiredPauseState() internal view returns (bool) {
        // slither-disable-next-line timestamp
        return lastPausedTimestamp > 0 && !paused();
    }

    function clearExpiredPause() internal returns (bool) {
        if (!expiredPauseState()) return false;

        lastPausedTimestamp = 0;
        _swapCostOffsetPeriod = swapCostOffsetMinInDays;
        return true;
    }

    function ensureNotStaleData(string memory name, uint256 dataTimestamp) internal view {
        // slither-disable-next-line timestamp
        if (block.timestamp - dataTimestamp > staleDataToleranceInSeconds) revert StaleData(name);
    }

    function convertUintToInt(uint256 value) internal pure returns (int256) {
        // slither-disable-next-line timestamp
        if (value > uint256(type(int256).max)) revert CannotConvertUintToInt();
        return int256(value);
    }
}

library SubSaturateMath {
    function subSaturate(uint256 self, uint256 other) internal pure returns (uint256) {
        if (other >= self) return 0;
        return self - other;
    }

    function subSaturate(int256 self, int256 other) internal pure returns (int256) {
        if (other >= self) return 0;
        return self - other;
    }
}

// TODO: move the updated interfaces below to the actual contracts
interface IDestinationVaultForStrategy is IDestinationVault {
    /// @notice Stats contract for this vault
    function getStats() external returns (IDexLSTStats);

    /// @notice get the marketplace rewards
    /// @return rewardTokens list of reward token addresses
    /// @return rewardRates list of reward rates
    function getMarketplaceRewards() external returns (uint256[] memory rewardTokens, uint256[] memory rewardRates);
}

interface ILMPVaultForStrategy is ILMPVault {
    /// @notice get a destinations last reported debt value
    /// @param dest the address of the target destination
    /// @return destinations last reported debt value
    function getDestinationInfo(address dest) external view returns (LMPDebt.DestinationInfo memory);

    /// @notice check if a destination is registered with the vault and not queued for removal
    /// @param dest the address of the target destination
    /// @return bool true if it is registered
    function isDestinationRegistered(address dest) external view returns (bool);

    /// @notice get if a destinationVault is queued for removal by the LMPVault
    /// @param dest the address of the target destination
    /// @return true if the target destination is queued for removal
    function isDestinationQueuedForRemoval(address dest) external view returns (bool);

    /// @notice add (or move to if it already exists) a destination to the head of the withdrawal queue
    function addToWithdrawalQueueHead(address destinationVault) external;

    /// @notice add (or move to if it already exists) a destination to the tail of the withdrawal queue
    function addToWithdrawalQueueTail(address destinationVault) external;
}
