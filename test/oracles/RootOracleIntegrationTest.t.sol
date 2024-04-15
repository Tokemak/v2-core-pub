// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count,var-name-mixedcase,max-line-length

import { Test } from "forge-std/Test.sol";
import {
    BAL_VAULT,
    CURVE_META_REGISTRY_MAINNET,
    WSTETH_MAINNET,
    STETH_MAINNET,
    RETH_MAINNET,
    DAI_MAINNET,
    USDC_MAINNET,
    USDT_MAINNET,
    CBETH_MAINNET,
    WETH_MAINNET,
    STETH_CL_FEED_MAINNET,
    RETH_CL_FEED_MAINNET,
    DAI_CL_FEED_MAINNET,
    USDC_CL_FEED_MAINNET,
    USDT_CL_FEED_MAINNET,
    CBETH_CL_FEED_MAINNET,
    USDC_DAI_USDT_BAL_POOL,
    CBETH_WSTETH_BAL_POOL,
    RETH_WETH_BAL_POOL,
    WSETH_WETH_BAL_POOL,
    ST_ETH_CURVE_LP_TOKEN_MAINNET,
    STETH_ETH_CURVE_POOL,
    THREE_CURVE_POOL_MAINNET_LP,
    WETH9_ADDRESS,
    CURVE_ETH,
    THREE_CURVE_MAINNET,
    USDC_IN_USD_CL_FEED_MAINNET,
    ETH_CL_FEED_MAINNET,
    STETH_STABLESWAP_NG_POOL,
    RETH_WSTETH_CURVE_POOL_LP,
    RETH_WSTETH_CURVE_POOL,
    RETH_WETH_CURVE_POOL,
    RETH_ETH_CURVE_LP,
    TOKE_MAINNET,
    WSTETH_WETH_MAV,
    USDT_IN_USD_CL_FEED_MAINNET,
    CRVUSD_MAINNET,
    USDP_CL_FEED_MAINNET,
    TUSD_CL_FEED_MAINNET,
    FRAX_MAINNET,
    SUSD_MAINNET,
    USDP_MAINNET,
    TUSD_MAINNET,
    USDP_CL_FEED_MAINNET,
    TUSD_CL_FEED_MAINNET,
    FRAX_CL_FEED_MAINNET,
    SUSD_CL_FEED_MAINNET,
    USDC_STABLESWAP_NG_POOL,
    USDT_STABLESWAP_NG_POOL,
    TUSD_STABLESWAP_NG_POOL,
    USDP_STABLESWAP_NG_POOL,
    FRAX_STABLESWAP_NG_POOL,
    SUSD_STABLESWAP_NG_POOL,
    CRV_ETH_CURVE_V2_LP,
    LDO_ETH_CURVE_V2_LP,
    CRV_ETH_CURVE_V2_POOL,
    LDO_ETH_CURVE_V2_POOL,
    CRV_CL_FEED_MAINNET,
    LDO_CL_FEED_MAINNET,
    CRV_MAINNET,
    LDO_MAINNET,
    STG_MAINNET,
    STG_CL_FEED_MAINNET,
    STG_USDC_CURVE_V2_LP,
    STG_USDC_V2_POOL,
    BADGER_MAINNET,
    WBTC_MAINNET,
    BADGER_CL_FEED_MAINNET,
    BTC_CL_FEED_MAINNET,
    WBTC_BADGER_CURVE_V2_LP,
    WBTC_BADGER_V2_POOL,
    FRXETH_MAINNET,
    MAV_POOL_INFORMATION,
    FRAX_USDC,
    FRAX_USDC_LP,
    SFRXETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL,
    STETH_WETH_CURVE_POOL_CONCENTRATED,
    STETH_WETH_CURVE_POOL_CONCENTRATED_LP,
    CBETH_ETH_V2_POOL_LP,
    CBETH_ETH_V2_POOL,
    WEETH_MAINNET,
    WEETH_RS_FEED_MAINNET,
    OSETH_MAINNET,
    EZETH_MAINNET,
    RSETH_MAINNET,
    SWETH_MAINNET,
    OSETH_RS_FEED_MAINNET,
    EZETH_RS_FEED_MAINNET,
    SWETH_RS_FEED_MAINNET,
    RSETH_RS_FEED_MAINNET
} from "../utils/Addresses.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { RootPriceOracle, IPriceOracle, ISpotPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController, Roles } from "src/security/AccessController.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { MavEthOracle } from "src/oracles/providers/MavEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { CrvUsdOracle } from "test/mocks/CrvUsdOracle.sol";

import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { CurveResolverMainnet, ICurveResolver, ICurveMetaRegistry } from "src/utils/CurveResolverMainnet.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";

/**
 * This series of tests compares expected values with contract calculated values for lp token pricing.  Below is a guide
 *      that can be used to add tests to this contract.
 *
 *      1) Using `vm.createSelectFork`, create a new fork at a recent block number.  This ensures that the safe price
 *            calculated is using recent data.
 *      2) Register new pool with `priceOracle`, check to see if individual tokens need to be registered with Chainlink
 *            or Tellor, and if lp token needs to be registered with a specific lp token oracle.
 *      3) Using an external source (coingecko, protocol UI, Etherscan), retrieve total value of the pool in USD.
 *            Divide this value by the current price of Eth in USD to get the total value of the pool in Eth.
 *      4) Normalize value of pool in Eth to e18, divide by total number of lp tokens (will already be in e18 in most
 *            cases). Normalize value returned to e18 decimals, this will be the value expected to be returned by
 *            the safe price contract.
 */
contract RootOracleIntegrationTest is Test {
    address public constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));

    SystemRegistry public systemRegistry;
    RootPriceOracle public priceOracle;
    AccessController public accessControl;
    CurveResolverMainnet public curveResolver;

    BalancerLPComposableStableEthOracle public balancerComposableOracle;
    BalancerLPMetaStableEthOracle public balancerMetaOracle;
    ChainlinkOracle public chainlinkOracle;
    CurveV1StableEthOracle public curveStableOracle;
    EthPeggedOracle public ethPegOracle;
    WstETHEthOracle public wstEthOracle;
    MavEthOracle public mavEthOracle;
    CurveV2CryptoEthOracle public curveCryptoOracle;
    CustomSetOracle public customSetOracle;
    CrvUsdOracle public crvUsdOracle;
    RedstoneOracle public redstoneOracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_474_729);

        // Set up system level contracts.
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        accessControl = new AccessController(address(systemRegistry));

        systemRegistry.setAccessController(address(accessControl));
        priceOracle = new RootPriceOracle(systemRegistry);

        systemRegistry.setRootPriceOracle(address(priceOracle));
        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));

        // Set up various oracle contracts
        balancerComposableOracle = new BalancerLPComposableStableEthOracle(systemRegistry, IBalancerVault(BAL_VAULT));
        balancerMetaOracle = new BalancerLPMetaStableEthOracle(systemRegistry, IBalancerVault(BAL_VAULT));
        chainlinkOracle = new ChainlinkOracle(systemRegistry);
        curveStableOracle = new CurveV1StableEthOracle(systemRegistry, ICurveResolver(curveResolver));
        ethPegOracle = new EthPeggedOracle(systemRegistry);
        wstEthOracle = new WstETHEthOracle(systemRegistry, WSTETH_MAINNET);
        mavEthOracle = new MavEthOracle(systemRegistry, MAV_POOL_INFORMATION);
        curveCryptoOracle = new CurveV2CryptoEthOracle(systemRegistry, ICurveResolver(curveResolver));
        customSetOracle = new CustomSetOracle(systemRegistry, 52 weeks); // Max age doesn't matter for testing.
        crvUsdOracle = new CrvUsdOracle(
            systemRegistry,
            IAggregatorV3Interface(USDC_IN_USD_CL_FEED_MAINNET),
            IAggregatorV3Interface(USDT_IN_USD_CL_FEED_MAINNET),
            IAggregatorV3Interface(ETH_CL_FEED_MAINNET)
        );
        redstoneOracle = new RedstoneOracle(systemRegistry);

        //
        // Make persistent for multiple forks
        //
        vm.makePersistent(address(systemRegistry));
        vm.makePersistent(address(accessControl));
        vm.makePersistent(address(priceOracle));
        vm.makePersistent(address(curveResolver));
        vm.makePersistent(address(balancerComposableOracle));
        vm.makePersistent(address(balancerMetaOracle));
        vm.makePersistent(address(chainlinkOracle));
        vm.makePersistent(address(curveStableOracle));
        vm.makePersistent(address(ethPegOracle));
        vm.makePersistent(address(wstEthOracle));
        vm.makePersistent(address(mavEthOracle));
        vm.makePersistent(address(curveCryptoOracle));
        vm.makePersistent(address(customSetOracle));
        vm.makePersistent(address(crvUsdOracle));
        vm.makePersistent(address(redstoneOracle));

        //
        // Root price oracle setup
        //
        priceOracle.registerMapping(STETH_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(RETH_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(DAI_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(USDC_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(USDT_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(CBETH_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(FRAX_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(SUSD_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(USDP_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(TUSD_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(CRVUSD_MAINNET, IPriceOracle(address(crvUsdOracle)));
        priceOracle.registerMapping(CRV_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(LDO_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(STG_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(BADGER_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(WBTC_MAINNET, IPriceOracle(address(chainlinkOracle)));
        priceOracle.registerMapping(ETH_IN_USD, IPriceOracle(address(chainlinkOracle)));

        //
        // Root price oracle setup for RedStone
        //
        priceOracle.registerMapping(WEETH_MAINNET, IPriceOracle((address(redstoneOracle))));
        priceOracle.registerMapping(OSETH_MAINNET, IPriceOracle((address(redstoneOracle))));
        priceOracle.registerMapping(EZETH_MAINNET, IPriceOracle((address(redstoneOracle))));
        priceOracle.registerMapping(RSETH_MAINNET, IPriceOracle((address(redstoneOracle))));
        priceOracle.registerMapping(SWETH_MAINNET, IPriceOracle((address(redstoneOracle))));

        // Balancer composable stable pool
        priceOracle.registerMapping(USDC_DAI_USDT_BAL_POOL, IPriceOracle(address(balancerComposableOracle)));

        // Balancer meta stable pool
        priceOracle.registerMapping(CBETH_WSTETH_BAL_POOL, IPriceOracle(address(balancerMetaOracle)));
        priceOracle.registerMapping(RETH_WETH_BAL_POOL, IPriceOracle(address(balancerMetaOracle)));
        priceOracle.registerMapping(WSETH_WETH_BAL_POOL, IPriceOracle(address(balancerMetaOracle)));

        // Curve V1
        priceOracle.registerMapping(ST_ETH_CURVE_LP_TOKEN_MAINNET, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(THREE_CURVE_POOL_MAINNET_LP, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(RETH_WSTETH_CURVE_POOL_LP, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(STETH_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(USDC_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(USDT_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(TUSD_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(USDP_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(FRAX_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));
        priceOracle.registerMapping(SUSD_STABLESWAP_NG_POOL, IPriceOracle(address(curveStableOracle)));

        // CurveV2
        priceOracle.registerMapping(RETH_ETH_CURVE_LP, IPriceOracle(address(curveCryptoOracle)));
        priceOracle.registerMapping(CRV_ETH_CURVE_V2_LP, IPriceOracle(address(curveCryptoOracle)));
        priceOracle.registerMapping(LDO_ETH_CURVE_V2_LP, IPriceOracle(address(curveCryptoOracle)));
        priceOracle.registerMapping(STG_USDC_CURVE_V2_LP, IPriceOracle(address(curveCryptoOracle)));
        priceOracle.registerMapping(WBTC_BADGER_CURVE_V2_LP, IPriceOracle(address(curveCryptoOracle)));
        priceOracle.registerMapping(CBETH_ETH_V2_POOL_LP, IPriceOracle(address(curveCryptoOracle)));

        // Mav
        priceOracle.registerMapping(WSTETH_WETH_MAV, IPriceOracle(address(mavEthOracle)));

        // Eth 1:1 setup
        priceOracle.registerMapping(WETH9_ADDRESS, IPriceOracle(address(ethPegOracle)));
        priceOracle.registerMapping(CURVE_ETH, IPriceOracle(address(ethPegOracle)));

        // Lst special pricing case setup
        priceOracle.registerMapping(WSTETH_MAINNET, IPriceOracle(address(wstEthOracle)));

        // Custom oracle
        priceOracle.registerMapping(FRXETH_MAINNET, IPriceOracle(address(customSetOracle)));

        // Chainlink setup
        chainlinkOracle.registerOracle(
            STETH_MAINNET,
            IAggregatorV3Interface(STETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            DAI_MAINNET, IAggregatorV3Interface(DAI_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            USDC_MAINNET,
            IAggregatorV3Interface(USDC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            USDT_MAINNET,
            IAggregatorV3Interface(USDT_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            CBETH_MAINNET,
            IAggregatorV3Interface(CBETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            FRAX_MAINNET,
            IAggregatorV3Interface(FRAX_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            USDP_MAINNET,
            IAggregatorV3Interface(USDP_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            TUSD_MAINNET,
            IAggregatorV3Interface(TUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            SUSD_MAINNET,
            IAggregatorV3Interface(SUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            CRV_MAINNET, IAggregatorV3Interface(CRV_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            LDO_MAINNET, IAggregatorV3Interface(LDO_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerOracle(
            BADGER_MAINNET,
            IAggregatorV3Interface(BADGER_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            2 hours
        );
        chainlinkOracle.registerOracle(
            WBTC_MAINNET,
            IAggregatorV3Interface(BTC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerOracle(
            ETH_IN_USD, IAggregatorV3Interface(ETH_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 0
        );

        // Curve V1 pool setup
        curveStableOracle.registerPool(STETH_ETH_CURVE_POOL, ST_ETH_CURVE_LP_TOKEN_MAINNET, true);
        curveStableOracle.registerPool(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, false);
        curveStableOracle.registerPool(STETH_STABLESWAP_NG_POOL, STETH_STABLESWAP_NG_POOL, false);
        curveStableOracle.registerPool(RETH_WSTETH_CURVE_POOL, RETH_WSTETH_CURVE_POOL_LP, false);
        curveStableOracle.registerPool(USDC_STABLESWAP_NG_POOL, USDC_STABLESWAP_NG_POOL, false);
        curveStableOracle.registerPool(USDT_STABLESWAP_NG_POOL, USDT_STABLESWAP_NG_POOL, false);
        curveStableOracle.registerPool(TUSD_STABLESWAP_NG_POOL, TUSD_STABLESWAP_NG_POOL, false);
        curveStableOracle.registerPool(USDP_STABLESWAP_NG_POOL, USDP_STABLESWAP_NG_POOL, false);
        curveStableOracle.registerPool(FRAX_STABLESWAP_NG_POOL, FRAX_STABLESWAP_NG_POOL, false);

        // Curve V2 pool setup
        curveCryptoOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, false);
        curveCryptoOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);
        curveCryptoOracle.registerPool(LDO_ETH_CURVE_V2_POOL, LDO_ETH_CURVE_V2_LP, false);
        curveCryptoOracle.registerPool(STG_USDC_V2_POOL, STG_USDC_CURVE_V2_LP, false);
        curveCryptoOracle.registerPool(WBTC_BADGER_V2_POOL, WBTC_BADGER_CURVE_V2_LP, false);
        curveCryptoOracle.registerPool(CBETH_ETH_V2_POOL, CBETH_ETH_V2_POOL_LP, false);

        // Custom oracle setup
        address[] memory tokens = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        tokens[0] = FRXETH_MAINNET;
        tokens[1] = SFRXETH_MAINNET;
        maxAges[0] = 50 weeks;
        maxAges[1] = 50 weeks;

        accessControl.setupRole(Roles.ORACLE_MANAGER_ROLE, address(this));
        accessControl.setupRole(Roles.CUSTOM_ORACLE_EXECUTOR, address(this));

        customSetOracle.registerTokens(tokens, maxAges);

        // Set up for spot pricing used across multiple test contracts.  Rest can be found in individual contracts.
        priceOracle.registerPoolMapping(THREE_CURVE_MAINNET, curveStableOracle);
        priceOracle.registerPoolMapping(STETH_ETH_CURVE_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(CBETH_ETH_V2_POOL, ISpotPriceOracle(curveCryptoOracle));
        priceOracle.registerPoolMapping(RETH_WETH_BAL_POOL, ISpotPriceOracle(balancerMetaOracle));
    }

    function _getTwoPercentTolerance(uint256 price) internal pure returns (uint256 upperBound, uint256 lowerBound) {
        uint256 twoPercentToleranceValue = (price * 2) / 100;

        upperBound = price + twoPercentToleranceValue;
        lowerBound = price - twoPercentToleranceValue;
    }
}

contract GetPriceInQuote is RootOracleIntegrationTest {
    function test_LowDecimalQuote() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_021_563);

        // stEth in usdc
        // calculated - 1724550123
        // safe price - 1736857822
        uint256 calculatedPrice = uint256(1_724_550_123);
        uint256 safePrice = priceOracle.getPriceInQuote(STETH_MAINNET, USDC_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_NonStableQuoteButMatchingDecimals() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_021_563);

        // usdt in crv
        // calculated - 2032995638000000000
        // safe price - 2017150178107977497
        uint256 calculatedPrice = uint256(2_032_995_638_000_000_000);
        uint256 safePrice = priceOracle.getPriceInQuote(USDT_MAINNET, CRV_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_WETHAsAQuoteAndNonMatchingDecimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_177_575);

        // Current ETH Price:  $2,381.53  - 1 ETH
        // Current USDC Price: $1.00      - 0.00042001e18 ETH

        uint256 calculatedPrice = uint256(0.00042001e18);
        uint256 safePrice = priceOracle.getPriceInQuote(USDC_MAINNET, WETH_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_WETHAsAQuoteAndMatchingDecimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_177_575);

        // Current ETH Price:  $2,381.53  - 1 ETH
        // Current CRV Price:  $0.4823    - 0.00020269e18 ETH

        uint256 calculatedPrice = uint256(0.00020269e18);
        uint256 safePrice = priceOracle.getPriceInQuote(CRV_MAINNET, WETH_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_LowDecimalAsQuoteWithWETH() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_177_575);

        // Current ETH Price:  $2,381.53  - 1 ETH
        // Current USDC Price: $1.00      - 0.00042001e18 ETH

        uint256 calculatedPrice = uint256(2_381_530_000);
        uint256 safePrice = priceOracle.getPriceInQuote(WETH_MAINNET, USDC_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }
}

///@dev Test LP token pricing
contract GetPriceInEth is RootOracleIntegrationTest {
    // Ensuring that all tokens and being used for guarded launch work as expected.
    function test_GuardedLaunchCoverage_getPriceInEth() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_323_090);

        //
        // Checking Chainlink price feeds.
        //

        // Off chain -  1099100000000000000
        // Safe price - 1099100000000000000
        uint256 offChain = uint256(1_099_100_000_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(RETH_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(offChain);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Off chain -  999319481500000000
        // Safe price - 999319481489392600
        offChain = uint256(999_319_481_500_000_000);
        safePrice = priceOracle.getPriceInEth(STETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Off chain -  1059015260299733800
        // Safe price - 1059015260299733800
        offChain = uint256(1_059_015_260_299_733_800);
        safePrice = priceOracle.getPriceInEth(CBETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_RedStoneOracle_getPriceInEth() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_419_462);

        //Redstone Oracle setup
        redstoneOracle.registerOracle(
            WEETH_MAINNET, IAggregatorV3Interface(WEETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        uint256 offChain = uint256(1_029_434_540_200_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(WEETH_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(offChain);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        //OSETH
        redstoneOracle.registerOracle(
            OSETH_MAINNET, IAggregatorV3Interface(OSETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        offChain = uint256(997_282_538_160_000_000);
        safePrice = priceOracle.getPriceInEth(OSETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        //SWETH
        redstoneOracle.registerOracle(
            SWETH_MAINNET, IAggregatorV3Interface(SWETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        offChain = uint256(1_045_404_656_580_000_000);
        safePrice = priceOracle.getPriceInEth(SWETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        //EZETH
        redstoneOracle.registerOracle(
            EZETH_MAINNET, IAggregatorV3Interface(EZETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        offChain = uint256(1_005_658_115_676_000_000);
        safePrice = priceOracle.getPriceInEth(EZETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        //RSETH
        redstoneOracle.registerOracle(
            RSETH_MAINNET, IAggregatorV3Interface(RSETH_RS_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 0
        );

        offChain = uint256(990_768_676_250_000_000);
        safePrice = priceOracle.getPriceInEth(RSETH_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(offChain);

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }
}

contract GetRangePricesLP is RootOracleIntegrationTest {
    function setUp() public override {
        super.setUp();

        // Map pool to oracle
        priceOracle.registerPoolMapping(USDC_DAI_USDT_BAL_POOL, balancerComposableOracle);

        priceOracle.registerPoolMapping(CBETH_WSTETH_BAL_POOL, balancerMetaOracle);
        priceOracle.registerPoolMapping(WSETH_WETH_BAL_POOL, balancerMetaOracle);

        priceOracle.registerPoolMapping(ST_ETH_CURVE_LP_TOKEN_MAINNET, curveStableOracle);
        priceOracle.registerPoolMapping(THREE_CURVE_POOL_MAINNET_LP, curveStableOracle);
        priceOracle.registerPoolMapping(RETH_WSTETH_CURVE_POOL_LP, curveStableOracle);
        priceOracle.registerPoolMapping(STETH_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(USDC_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(USDT_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(TUSD_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(USDP_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(FRAX_STABLESWAP_NG_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(SUSD_STABLESWAP_NG_POOL, curveStableOracle);

        priceOracle.registerPoolMapping(RETH_WETH_CURVE_POOL, curveCryptoOracle);
        priceOracle.registerPoolMapping(CRV_ETH_CURVE_V2_POOL, curveCryptoOracle);
        priceOracle.registerPoolMapping(LDO_ETH_CURVE_V2_POOL, curveCryptoOracle);
        priceOracle.registerPoolMapping(STG_USDC_V2_POOL, curveCryptoOracle);
        priceOracle.registerPoolMapping(WBTC_BADGER_V2_POOL, curveCryptoOracle);

        // 2% tolerance to be considered safe
        priceOracle.setSafeSpotPriceThreshold(USDC_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(DAI_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(USDT_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(RETH_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(WETH9_ADDRESS, 200);
        priceOracle.setSafeSpotPriceThreshold(CBETH_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(WSTETH_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(STETH_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(CRVUSD_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(TUSD_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(USDP_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(FRAX_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(SUSD_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(CRV_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(LDO_MAINNET, 200);
        priceOracle.setSafeSpotPriceThreshold(STG_MAINNET, 200);
        // and 8% for those with higher volatility and lower liquidity
        priceOracle.setSafeSpotPriceThreshold(BADGER_MAINNET, 800);
        priceOracle.setSafeSpotPriceThreshold(WBTC_MAINNET, 800);
    }

    function _verifySafePriceByPercentTolerance(
        uint256 expectedPrice,
        uint256 safePrice,
        uint256 spotPrice,
        uint256 tolerancePercent,
        bool isSpotSafe
    ) internal {
        uint256 toleranceValue = (expectedPrice * tolerancePercent) / 100;

        uint256 upperBound = expectedPrice + toleranceValue;
        uint256 lowerBound = expectedPrice - toleranceValue;

        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);

        assertTrue(isSpotSafe);
    }

    function test_BalComposableStablePoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_350);

        priceOracle.setSafeSpotPriceThreshold(USDC_DAI_USDT_BAL_POOL, 200);

        // Calculated WETH - 573334720000000
        uint256 calculatedPrice = uint256(0.00057333472 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(USDC_DAI_USDT_BAL_POOL, USDC_DAI_USDT_BAL_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.001509439841252267
        calculatedPrice = uint256(1_001_509);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDC_DAI_USDT_BAL_POOL, USDC_DAI_USDT_BAL_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);
    }

    function test_BalMetaStablePoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_744);

        // 1)

        // Calculated WETH - 1.010052287000000000
        uint256 calculatedPrice = uint256(1.010052287 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(CBETH_WSTETH_BAL_POOL, CBETH_WSTETH_BAL_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1759.6625918
        calculatedPrice = uint256(1_759_662_591);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(CBETH_WSTETH_BAL_POOL, CBETH_WSTETH_BAL_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 2)

        // Calculated WETH - 1.023468806000000000
        calculatedPrice = uint256(1.023468806 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1783.03618037
        calculatedPrice = uint256(1_783_036_180);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 3)

        // Calculated WETH - 1.035273715000000000
        calculatedPrice = uint256(1.035273715 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(WSETH_WETH_BAL_POOL, WSETH_WETH_BAL_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1803.60210259
        calculatedPrice = uint256(1_803_602_102);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(WSETH_WETH_BAL_POOL, WSETH_WETH_BAL_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);
    }

    function test_CurveStableV1PoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_426);

        // 1)
        // Calculated WETH - 1.073735977000000000
        uint256 calculatedPrice = uint256(1.073735977 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(ST_ETH_CURVE_LP_TOKEN_MAINNET, STETH_ETH_CURVE_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1870.60913233
        calculatedPrice = uint256(1_870_609_132);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(ST_ETH_CURVE_LP_TOKEN_MAINNET, STETH_ETH_CURVE_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 2)
        // Calculated WETH - 587546836000000 // 0.000587546836 * 10 ** 18
        calculatedPrice = uint256(587_546_836_000_000);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(THREE_CURVE_POOL_MAINNET_LP, THREE_CURVE_MAINNET, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.02359472034
        calculatedPrice = uint256(1_023_594);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(THREE_CURVE_POOL_MAINNET_LP, THREE_CURVE_MAINNET, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 3)
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_480_014);

        // Calculated WETH - 1.098321582000000000
        calculatedPrice = uint256(1.098321582 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_WSTETH_CURVE_POOL_LP, RETH_WSTETH_CURVE_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1910.14597934
        calculatedPrice = uint256(1_910_145_979);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_WSTETH_CURVE_POOL_LP, RETH_WSTETH_CURVE_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);
    }

    function test_CurveStableSwapNGPools() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_480_014);

        // 1)
        // Calculated WETH - 1.006028244000000000
        uint256 calculatedPrice = uint256(1.006028244 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(STETH_STABLESWAP_NG_POOL, STETH_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1749.63402055
        calculatedPrice = uint256(1_749_634_020);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(STETH_STABLESWAP_NG_POOL, STETH_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 2)
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_586_413);

        // Calculated WETH - 540613701000000
        calculatedPrice = uint256(0.000540613701 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDC_STABLESWAP_NG_POOL, USDC_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.012780
        calculatedPrice = uint256(1_012_780);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDC_STABLESWAP_NG_POOL, USDC_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 3)
        // Calculated WETH - 540416370000000
        calculatedPrice = uint256(0.00054041637 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDT_STABLESWAP_NG_POOL, USDT_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.01241062339
        calculatedPrice = uint256(1_012_410);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDT_STABLESWAP_NG_POOL, USDT_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 4)
        // Calculated WETH - 539978431000000
        calculatedPrice = uint256(0.000539978431 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(TUSD_STABLESWAP_NG_POOL, TUSD_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.01159019285
        calculatedPrice = uint256(1_011_590);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(TUSD_STABLESWAP_NG_POOL, TUSD_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 5)
        // Calculated WETH - 540443002000000
        calculatedPrice = uint256(0.000540443002 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDP_STABLESWAP_NG_POOL, USDP_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.01246051552
        calculatedPrice = uint256(1_012_460);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(USDP_STABLESWAP_NG_POOL, USDP_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 6)
        // Calculated WETH - 539914597000000
        calculatedPrice = uint256(0.000539914597 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(FRAX_STABLESWAP_NG_POOL, FRAX_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.01147060687
        calculatedPrice = uint256(1_011_470);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(FRAX_STABLESWAP_NG_POOL, FRAX_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 7)
        curveStableOracle.registerPool(SUSD_STABLESWAP_NG_POOL, SUSD_STABLESWAP_NG_POOL, false);

        // Calculated WETH - 539909058000000
        calculatedPrice = uint256(0.000539909058 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(SUSD_STABLESWAP_NG_POOL, SUSD_STABLESWAP_NG_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.01146023017
        calculatedPrice = uint256(1_011_460);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(SUSD_STABLESWAP_NG_POOL, SUSD_STABLESWAP_NG_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);
    }

    /**
     * @notice Tested against multiple v2 pools that we are not using to test validity of approach
     */
    // TODO: Badger / wbtc,
    function test_CurveV2Pools1() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_672_343);

        // 1)

        // Calculated WETH - 2.079485290000000000
        uint256 calculatedPrice = uint256(2.07948529 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_ETH_CURVE_LP, RETH_WETH_CURVE_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 3895.68694743
        calculatedPrice = uint256(3_895_686_947);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(RETH_ETH_CURVE_LP, RETH_WETH_CURVE_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 2)

        // Calculated WETH - 42945287200000000
        calculatedPrice = uint256(0.0429452872 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(CRV_ETH_CURVE_V2_LP, CRV_ETH_CURVE_V2_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 80.4794682128
        calculatedPrice = uint256(80_479_468);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(CRV_ETH_CURVE_V2_LP, CRV_ETH_CURVE_V2_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 3)

        // Calculated WETH - 64666948400000000
        calculatedPrice = uint256(0.064695922392289196 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(LDO_ETH_CURVE_V2_LP, LDO_ETH_CURVE_V2_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 121.240158563
        calculatedPrice = uint256(121_240_158);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(LDO_ETH_CURVE_V2_LP, LDO_ETH_CURVE_V2_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        //
        // Non-ETH tests
        //
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_914_103);

        chainlinkOracle.registerOracle(
            STG_MAINNET, IAggregatorV3Interface(STG_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 24 hours
        );

        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        tokens[0] = FRXETH_MAINNET;
        prices[0] = 998_126_960_000_000_000;
        timestamps[0] = block.timestamp;
        customSetOracle.setPrices(tokens, prices, timestamps);

        // 4)

        // Calculated WETH - 898924164000000
        calculatedPrice = uint256(0.000898924164 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(STG_USDC_CURVE_V2_LP, STG_USDC_V2_POOL, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.6576341369
        calculatedPrice = uint256(1_657_634);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(STG_USDC_CURVE_V2_LP, STG_USDC_V2_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // 5)

        // Calculated WETH - 280364973000000000
        calculatedPrice = uint256(0.280364973 * 10 ** 18);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(WBTC_BADGER_CURVE_V2_LP, WBTC_BADGER_V2_POOL, WETH9_ADDRESS);

        // _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 4, isSpotSafe);

        // Calculated USDC - 516.998617511
        calculatedPrice = uint256(516_998_617);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(WBTC_BADGER_CURVE_V2_LP, WBTC_BADGER_V2_POOL, USDC_MAINNET);

        // _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 4, isSpotSafe);
    }

    function test_EthInUsdPath() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_310);

        chainlinkOracle.removeOracleRegistration(USDC_MAINNET);
        chainlinkOracle.registerOracle(
            USDC_MAINNET,
            IAggregatorV3Interface(USDC_IN_USD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.USD,
            24 hours
        );

        // Calculated WETH - 588167942000000
        uint256 calculatedPrice = uint256(0.000588167942 * 10 ** 18);
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) =
            priceOracle.getRangePricesLP(THREE_CURVE_POOL_MAINNET_LP, THREE_CURVE_MAINNET, WETH9_ADDRESS);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);

        // Calculated USDC - 1.02694122673
        calculatedPrice = uint256(1_026_941);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(THREE_CURVE_POOL_MAINNET_LP, THREE_CURVE_MAINNET, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 2, isSpotSafe);
    }

    // Pool coverage for guarded launch.
    function test_GuardedLaunchCoverage_getRangePricesLp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_334_597);

        // stEth / Eth
        // Calculated - 1094195215365798428
        uint256 calculatedPrice = uint256(1_094_195_215_365_798_428);
        (uint256 spot, uint256 safe, bool isSafe) =
            priceOracle.getRangePricesLP(ST_ETH_CURVE_LP_TOKEN_MAINNET, STETH_ETH_CURVE_POOL, WETH_MAINNET);
        _verifySafePriceByPercentTolerance(calculatedPrice, safe, spot, 2, isSafe);

        // cbEth / Eth
        // Calculated - 2082488694887636300
        calculatedPrice = uint256(2_082_488_694_887_636_300);
        (spot, safe, isSafe) = priceOracle.getRangePricesLP(CBETH_ETH_V2_POOL_LP, CBETH_ETH_V2_POOL, WETH_MAINNET);
        _verifySafePriceByPercentTolerance(calculatedPrice, safe, spot, 2, isSafe);
    }
}

/**
 * These tests compare values returned for floor and ceiling pricing and externally calculated values. The
 *    goal of these tests is to test each individual if statement in the `getFloorCeilingPrice` function. The
 *    general guideline is below
 *
 * 1) These tests made extensive use of console logging, both in the test file and in the `RootPriceOracle`
 *    contract.  A general idea of what was logged:
 *    - Calculated floor and ceiling prices, actual quote tokens, and tokens priced within the `RootPrice`
 *      contract.  This allows the tester to see which spot pricing operation will be floor and ceiling,
 *      as this information is not readily available.
 *    - Prices calculated using `ISpotPriceOracle` operations.  This operation was used to obtain raw spot
 *      prices, ie those that had not been adjusted for quote or decimals yet.
 *    - Floor and ceiling prices returned from the `getFloorCeilingPrice` contract call.
 *
 * 2) Once the floor and ceiling price path base and quote are determined, getting a raw spot price is needed.
 *    The easiest way to do this is to use the `ISpotPriceOracle.getSpotPrice` function.
 *
 * 3) If the raw spot price is not in the decimals or quote desired, it will have to adjusted.  For decimals,
 *    multiple or divide by 10 raised to the exponent of the number of decimals needed.  For adjusting quote,
 *    use an external source (like Coingecko) to get prices to adjust by.  The operation for doing this can
 *    be found by following `_enforceQuoteToken`.
 *
 * 4) Get reserves and lp `totalSupply` from Etherscan. These may have to be adjusted to the decimals of the
 *    `inQuote` token.
 *
 * 5) Use the adjusted spot price, total reserves, and total supply to calculate an expected floor or
 *    ceiling price.
 *
 * NOTE - In some cases the calculated price and returned price come out to be exactly the same.  There
 *    are a couple of reasons for this:
 *    - This can happen when a quote token adjustment does not happen.
 *    - This can also happen when lp supply and reserves retrieved from Etherscan are the same as what
 *      is being used in spot price calculations.  This will happen when no trades have occurred on the
 *      pool between contract calculations and getting information on the UI.
 */
contract GetFloorCeilingPrice is RootOracleIntegrationTest {
    // Registers pools and tokens that have not been registered.
    function setUp() public override {
        super.setUp();

        curveStableOracle.registerPool(FRAX_USDC, FRAX_USDC_LP, false);
        curveStableOracle.registerPool(STETH_WETH_CURVE_POOL_CONCENTRATED, STETH_WETH_CURVE_POOL_CONCENTRATED_LP, false);
        priceOracle.registerMapping(SFRXETH_MAINNET, IPriceOracle(address(customSetOracle)));
        priceOracle.registerPoolMapping(FRAX_USDC, ISpotPriceOracle(curveStableOracle));
        priceOracle.registerPoolMapping(WSETH_RETH_SFRXETH_BAL_POOL, ISpotPriceOracle(balancerComposableOracle));
        priceOracle.registerPoolMapping(RETH_WETH_CURVE_POOL, ISpotPriceOracle(curveCryptoOracle));
        priceOracle.registerPoolMapping(RETH_WSTETH_CURVE_POOL, ISpotPriceOracle(curveStableOracle));
        priceOracle.registerPoolMapping(STETH_WETH_CURVE_POOL_CONCENTRATED, ISpotPriceOracle(curveStableOracle));
        priceOracle.registerPoolMapping(CBETH_WSTETH_BAL_POOL, ISpotPriceOracle(balancerMetaOracle));
    }

    // ----------------
    // Testing quote decimal adjustments.
    // ----------------

    /**
     * Testing that a single token in a pool adjusts to a quote correctly with no decimal conversion. This
     *    is accomplished by using a pool containing tokens that have 18 decimals and using one of the
     *    tokens in the pool as quote.  Only looking at the price that touches the path that converts to
     *    the desired quote.  This method eliminates any lp or reserve decimal adjustments.
     *
     *  Getting ceiling price as that is the path that touches `_enforceQuoteToken`, which is what is
     *    needed to adjust the quote.
     *
     * Ceiling price returned -   1088774876286734804
     * Ceiling price calculated - 1087794810604558466.
     */
    function test_QuoteTokenAdjustsCorrectly_SameDecimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_215_238);

        uint256 calculatedPrice = 1_087_794_810_604_558_466;
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(STETH_ETH_CURVE_POOL, ST_ETH_CURVE_LP_TOKEN_MAINNET, WETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    /**
     * This test follows a similar pattern to the one above, except that this one requires a conversion to a
     *    token with differing decimals.  This will also use a token already in the pool.  This test path
     *    will also require a reserves adjustment.
     *
     * Using path where USDC is priced in FRAX. This is because `_enforceQuoteToken`  will have to adjust decimals
     *    from the actual quote token FRAX (18 decimals) to the desired quote tokens of USDC (6 decimals).  This
     *    will be the floor price.
     *
     * Floor price returned -   985390
     * Floor price calculated - 1000014
     */
    function test_QuoteTokenAdjustsProperly_DifferingDecimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_219_670);

        uint256 calculatedPrice = 1_000_014;
        uint256 floorPrice = priceOracle.getFloorCeilingPrice(FRAX_USDC, FRAX_USDC_LP, USDC_MAINNET, false);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);
    }

    /**
     * This test checks the path where the actual quote token is equal to the requested quote token.
     *
     * Values came out the same because quote did not have to be adjusted for in this case.
     *
     * calculated - 1059662978932490257
     * Returned -   1059662978932490257
     */
    function test_CorrectPriceReturned_NoQuoteAdjustment() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_219_797);

        uint256 calculatedPrice = 1_059_662_978_932_490_257;
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(RETH_WSTETH_CURVE_POOL, RETH_WSTETH_CURVE_POOL_LP, RETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    // ----------------
    // Testing reserve decimal adjustments.
    // ----------------

    /**
     * This test checks the path where the token priced has a greater number of decimals than the quote token,
     *    meaning that the reserves need to be scaled down to match the decimals of the quote token.  This path
     *    will test the case where frax is the token being priced, being swapped to usdc in the spot price
     *    calculation.  This means that the spot price will not have to be adjusted, but the reserves will.
     *
     * Value are the same because quote token did not need to be adjusted.
     *
     * Calculated - 999980
     * Returned -   999980
     */
    function test_ReservesAdjustCorrectly_PricedTokenDecimals_GreaterThan_RequestedQuoteToken() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_220_106);

        uint256 calculatedPrice = 999_980;
        uint256 ceilingPrice = priceOracle.getFloorCeilingPrice(FRAX_USDC, FRAX_USDC_LP, USDC_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    /**
     * This test checks the situation where the token priced has a lesser number of decimals than the quote
     *      token and reserves need to be scaled up.  This test is run in a very similar way to the one above.
     *      USDC swapped to FRAX here to get desired effect.
     *
     * Calculated - 1003891960978409778
     * Returned -   1003882610998542675
     */
    function test_ReservesAdjustCorrectly_PricedTokenDecimals_LessThan_RequestedQuoteToken() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_220_106);

        uint256 calculatedPrice = 1_003_891_960_978_409_778;
        uint256 floorPrice = priceOracle.getFloorCeilingPrice(FRAX_USDC, FRAX_USDC_LP, FRAX_MAINNET, false);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);
    }

    /**
     * This test checks to make sure that everything runs correctly when decimals do not need to be scaled
     *    for the reserves of the token being priced.  Uses tokens of the same decimals, and use a quote token
     *    that does not need to be adjusted to avoid extraneous calculations.
     *
     * Calculated - 2230943235103642383
     * Returned -   2230943235103642383
     */
    function test_ReservesWorkCorrectly_EqualDecimals_PricedAndQuote() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_220_272);

        uint256 calculatedPrice = 2_230_943_235_103_642_383;
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, WETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    // ----------------
    // Testing lp token decimal adjustments.
    // ----------------

    /**
     * Testing for when an lp token has a greater amount of decimals than the requested quote token.  Using
     *    a specific path in three pool (swapping usdc -> usdt or vice versa) with a quote in either of those
     *    tokens allows most decimal adjustments aside from the lp adjustment to be skipped.
     *
     * Calculated - 1029645
     * Returned -   1029645
     */
    function test_LPTokenAdjustsProperly_DecimalsGreaterThanQuote() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_226_814);

        uint256 calculatedPrice = 1_029_645;
        uint256 floorPrice =
            priceOracle.getFloorCeilingPrice(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, USDC_MAINNET, false);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);
    }

    // ----------------
    // Testing pricing returns for pools > 2 tokens.
    // ----------------

    /**
     * Testing floor and ceiling price using Balancer 3 lst pool.  All prices are converted to weth to
     *    hit as many paths as possible, reason being that no specific paths are being tested for here.
     *
     * Floor calc -       1010811324660508142
     * Floor returned -   1007607314560983751
     *
     * Ceiling calc -     1088375142327765147
     * Ceiling returned - 1084925275015227212
     */
    function test_PoolWithGreaterThanTwoTokens_All18Decimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_221_345);

        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        tokens[0] = SFRXETH_MAINNET;
        prices[0] = 1_075_200_000_000_000_000;
        timestamps[0] = block.timestamp;
        customSetOracle.setPrices(tokens, prices, timestamps);

        uint256 calculatedFloorPrice = 1_010_811_324_660_508_142;
        uint256 calculatedCeilingPrice = 1_088_375_142_327_765_147;

        uint256 floorPrice = priceOracle.getFloorCeilingPrice(
            WSETH_RETH_SFRXETH_BAL_POOL, WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET, false
        );
        uint256 ceilingPrice = priceOracle.getFloorCeilingPrice(
            WSETH_RETH_SFRXETH_BAL_POOL, WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET, true
        );

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    /**
     * NOTE - Due to close token prices and slight inconsistencies calculating prices externally, the calculated
     *    floor price is actually higher than the calculated ceiling here.
     *
     * Ceiling calculated - 1028903
     * Ceiling returned -   1032948
     *
     * Floor calculated - 1029645
     * Floor returned -   1029645
     */
    function test_PoolWithGreaterThanTwoTokens_LessThan18Decimals() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_226_814);

        uint256 calculatedFloorPrice = 1_029_645;
        uint256 calculatedCeilingPrice = 1_028_903;

        uint256 floorPrice =
            priceOracle.getFloorCeilingPrice(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, USDC_MAINNET, false);
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, USDC_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    // ----------------
    // Test floor and ceiling for each `ISpotPriceOracle` contract.
    // ----------------

    /**
     * Ceiling calculated - 1069285457353509362
     * Ceiling returned -   1068726638138250848
     *
     * Floor calculated -  1068726638138250848
     * Floor returned -    1068101963650201584
     */
    function test_CurveV1WithFloorCeilingPrice() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_221_928);

        uint256 calculatedFloorPrice = 1_068_726_638_138_250_848;
        uint256 calculatedCeilingPrice = 1_069_285_457_353_509_362;

        uint256 floorPrice = priceOracle.getFloorCeilingPrice(
            STETH_WETH_CURVE_POOL_CONCENTRATED, STETH_WETH_CURVE_POOL_CONCENTRATED_LP, WETH_MAINNET, false
        );
        uint256 ceilingPrice = priceOracle.getFloorCeilingPrice(
            STETH_WETH_CURVE_POOL_CONCENTRATED, STETH_WETH_CURVE_POOL_CONCENTRATED_LP, WETH_MAINNET, true
        );

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    /**
     * Ceiling calculated - 2230745562574419327
     * Ceiling returned -   2230745562574419327
     *
     * Floor calculated - 2030687038850489149
     * Floor returned -   2029600647904936906
     */
    function test_CurveV2WithFloorCeilingPrice() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_221_993);

        uint256 calculatedFloorPrice = 2_030_687_038_850_489_149;
        uint256 calculatedCeilingPrice = 2_230_745_562_574_419_327;

        uint256 floorPrice =
            priceOracle.getFloorCeilingPrice(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, WETH_MAINNET, false);
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, WETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    /**
     * This test works for both Balancer oracles.  This is because they use the same logic for spot pricing
     *    operations.
     *
     * Ceiling calculated - 1073423773587674177
     * Ceiling returned -   1073371513891114941
     *
     * Floor calculated - 982424180325051279
     * Floor returned -   983807745569554423
     */
    function test_BalancerWithFloorCeilingPrice() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_222_223);

        uint256 calculatedFloorPrice = 982_424_180_325_051_279;
        uint256 calculatedCeilingPrice = 1_073_423_773_587_674_177;

        uint256 floorPrice =
            priceOracle.getFloorCeilingPrice(CBETH_WSTETH_BAL_POOL, CBETH_WSTETH_BAL_POOL, WETH_MAINNET, false);
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(CBETH_WSTETH_BAL_POOL, CBETH_WSTETH_BAL_POOL, WETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }

    function test_MavWithFloorCeilingPrice() public { }

    // ----------------
    // Floor ceiling coverage for guarded launch pools
    // ----------------

    function test_GuardedLaunchCoverage_getFloorCeilingPrice() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_327_652);

        // Calculated floor - 2046011565273104385
        // Returned floor -   2030948371758995775

        // Calculated ceiling - 2148883232859786676
        // Returned ceiling -   2148883232859786676
        uint256 calculatedFloorPrice = uint256(2_046_011_565_273_104_385);
        uint256 calculatedCeilingPrice = uint256(2_148_883_232_859_786_676);
        uint256 floorPrice =
            priceOracle.getFloorCeilingPrice(CBETH_ETH_V2_POOL, CBETH_ETH_V2_POOL_LP, WETH_MAINNET, false);
        uint256 ceilingPrice =
            priceOracle.getFloorCeilingPrice(CBETH_ETH_V2_POOL, CBETH_ETH_V2_POOL_LP, WETH_MAINNET, true);

        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);

        // Calculated floor - 982553208204218845
        // Returned floor -   987907961189286400

        // Calculated ceiling - 1081153457231268549
        // Returned ceiling -   1062350055329237532
        calculatedFloorPrice = uint256(982_553_208_204_218_845);
        calculatedCeilingPrice = uint256(1_081_153_457_231_268_549);
        floorPrice = priceOracle.getFloorCeilingPrice(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, WETH_MAINNET, false);
        ceilingPrice = priceOracle.getFloorCeilingPrice(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, WETH_MAINNET, true);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedFloorPrice);
        assertGt(upperBound, floorPrice);
        assertLt(lowerBound, floorPrice);

        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedCeilingPrice);
        assertGt(upperBound, ceilingPrice);
        assertLt(lowerBound, ceilingPrice);
    }
}

contract GetSpotPriceInEth is RootOracleIntegrationTest {
    function setUp() public override {
        super.setUp();

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_328_511);
    }

    // stEth / Eth CurveV1 pool
    function test_getSpotPriceInEth_StEthEthCurveV1Pool() public {
        // Fee - 1000000
        // Fee precision - 1e10

        // stEth -> eth.
        // dy - 999200642198174334
        // Calculated - 999300572255399873
        // Returned -   999300579110966650
        uint256 calculatedSpot = uint256(999_300_572_255_399_873);
        uint256 spotPrice = priceOracle.getSpotPriceInEth(STETH_MAINNET, STETH_ETH_CURVE_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedSpot);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);

        // eth -> stEth, converted to weth
        // dy - 1000598352626011108
        // Calculated - 1000698422468257933
        // Returned -   999828761519930401
        calculatedSpot = uint256(1_000_698_422_468_257_933);
        spotPrice = priceOracle.getSpotPriceInEth(CURVE_ETH, STETH_ETH_CURVE_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedSpot);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);
    }

    // cbEth / Eth CurveV2 pool
    function test_getSpotPriceInEth_CbEthEthCurveV2Pool() public {
        // Fee - 5156752
        // Fee precision - 1e10

        // cbEth -> eth.
        // dy - 1057393336005537232
        // Calculated - 1057938888853634607
        // Returned -   1057938888853634607
        uint256 calculatedSpot = uint256(1_057_938_888_853_634_607);
        uint256 spotPrice = priceOracle.getSpotPriceInEth(CBETH_MAINNET, CBETH_ETH_V2_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedSpot);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);

        // Eth -> cbEth.
        // dy - 944617789553842169
        // Calculated - 1000582829551398187
        // Returned -   999877159857762504
        calculatedSpot = uint256(1_000_582_829_551_398_187);
        spotPrice = priceOracle.getSpotPriceInEth(CURVE_ETH, CBETH_ETH_V2_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedSpot);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);
    }

    // rEth / weth Bal pool
    function test_getSpotPriceInEth_RethWethBalPool() public {
        // rEth -> weth
        // Calculated - 1099053184971559591
        // Returned   - 1099053184971559591
        uint256 calculated = uint256(1_099_053_184_971_559_591);
        uint256 spotPrice = priceOracle.getSpotPriceInEth(RETH_MAINNET, RETH_WETH_BAL_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculated);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);

        // weth -> rEth
        // Calculated - 1000039728314864482
        // Returned   - 1000255127611642698
        calculated = uint256(1_000_039_728_314_864_482);
        spotPrice = priceOracle.getSpotPriceInEth(WETH_MAINNET, RETH_WETH_BAL_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculated);
        assertGt(upperBound, spotPrice);
        assertLt(lowerBound, spotPrice);
    }
}
