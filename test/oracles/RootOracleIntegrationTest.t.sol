// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase
// solhint-disable max-states-count
import { Test } from "forge-std/Test.sol";
import {
    BAL_VAULT,
    CURVE_META_REGISTRY_MAINNET,
    TELLOR_ORACLE,
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
    STETH_ETH_UNIV2,
    ETH_USDT_UNIV2,
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
    MAV_POOL_INFORMATION
} from "../utils/Addresses.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { RootPriceOracle, IPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController, Roles } from "src/security/AccessController.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { UniswapV2EthOracle } from "src/oracles/providers/UniswapV2EthOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { MavEthOracle } from "src/oracles/providers/MavEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";
import { CrvUsdOracle } from "test/mocks/CrvUsdOracle.sol";

import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { CurveResolverMainnet, ICurveResolver, ICurveMetaRegistry } from "src/utils/CurveResolverMainnet.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

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
    UniswapV2EthOracle public uniV2EthOracle;
    WstETHEthOracle public wstEthOracle;
    MavEthOracle public mavEthOracle;
    CurveV2CryptoEthOracle public curveCryptoOracle;
    CustomSetOracle public customSetOracle;
    CrvUsdOracle public crvUsdOracle;

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
        uniV2EthOracle = new UniswapV2EthOracle(systemRegistry);
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
        vm.makePersistent(address(uniV2EthOracle));
        vm.makePersistent(address(wstEthOracle));
        vm.makePersistent(address(mavEthOracle));
        vm.makePersistent(address(curveCryptoOracle));
        vm.makePersistent(address(customSetOracle));
        vm.makePersistent(address(crvUsdOracle));

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

        // UniV2
        priceOracle.registerMapping(STETH_ETH_UNIV2, IPriceOracle(address(uniV2EthOracle)));
        priceOracle.registerMapping(ETH_USDT_UNIV2, IPriceOracle(address(uniV2EthOracle)));

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
        chainlinkOracle.registerChainlinkOracle(
            STETH_MAINNET,
            IAggregatorV3Interface(STETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            RETH_MAINNET,
            IAggregatorV3Interface(RETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            DAI_MAINNET, IAggregatorV3Interface(DAI_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            USDC_MAINNET,
            IAggregatorV3Interface(USDC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            USDT_MAINNET,
            IAggregatorV3Interface(USDT_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            CBETH_MAINNET,
            IAggregatorV3Interface(CBETH_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            FRAX_MAINNET,
            IAggregatorV3Interface(FRAX_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            USDP_MAINNET,
            IAggregatorV3Interface(USDP_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            TUSD_MAINNET,
            IAggregatorV3Interface(TUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            SUSD_MAINNET,
            IAggregatorV3Interface(SUSD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            CRV_MAINNET, IAggregatorV3Interface(CRV_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            LDO_MAINNET, IAggregatorV3Interface(LDO_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.ETH, 24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            BADGER_MAINNET,
            IAggregatorV3Interface(BADGER_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            2 hours
        );
        chainlinkOracle.registerChainlinkOracle(
            WBTC_MAINNET,
            IAggregatorV3Interface(BTC_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );
        chainlinkOracle.registerChainlinkOracle(
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

        // Uni pool setup
        uniV2EthOracle.register(STETH_ETH_UNIV2);
        uniV2EthOracle.register(ETH_USDT_UNIV2);

        // Custom oracle setup
        address[] memory tokens = new address[](1);
        uint256[] memory maxAges = new uint256[](1);
        tokens[0] = FRXETH_MAINNET;
        maxAges[0] = 50 weeks;

        accessControl.setupRole(Roles.ORACLE_MANAGER_ROLE, address(this));

        customSetOracle.registerTokens(tokens, maxAges);
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
    function test_BalComposableStablePoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_350);

        // Calculated - 573334720000000
        // Safe price - 575991341828605
        uint256 calculatedPrice = uint256(573_334_720_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(USDC_DAI_USDT_BAL_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_CurveStableV1PoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_426);

        // Calculated - 1073735977000000000
        // Safe price - 1073637176979605953
        uint256 calculatedPrice = uint256(1_073_735_977_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(ST_ETH_CURVE_LP_TOKEN_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 587546836000000
        // Safe price - 590481873156925
        calculatedPrice = uint256(587_546_836_000_000);
        safePrice = priceOracle.getPriceInEth(THREE_CURVE_POOL_MAINNET_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Newer tests, new fork.
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_480_014);

        // Calculated - 1098321582000000000
        // Safe price - 1077905860822595469
        calculatedPrice = uint256(1_098_321_582_000_000_000);
        safePrice = priceOracle.getPriceInEth(RETH_WSTETH_CURVE_POOL_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_UniV2PoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_530);

        // Calculated - 2692923915000000000
        // Safe price - 2719124222286442720
        uint256 calculatedPrice = uint256(2_692_923_915_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(STETH_ETH_UNIV2);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 111063607400000000000000
        // Safe price - 111696966269313545001725
        calculatedPrice = uint256(111_063_607_400_000_000_000_000);
        safePrice = priceOracle.getPriceInEth(ETH_USDT_UNIV2);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_BalMetaStablePoolOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_744);

        // Calculated - 1010052287000000000
        // Safe price - 1049623347233950707
        uint256 calculatedPrice = uint256(1_010_052_287_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(CBETH_WSTETH_BAL_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 1023468806000000000
        // Safe price - 1023189295745953671
        calculatedPrice = uint256(1_023_691_743_000_000_000);
        safePrice = priceOracle.getPriceInEth(RETH_WETH_BAL_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 1035273715000000000
        // Safe price - 1035531137827401614
        calculatedPrice = uint256(1_034_447_288_000_000_000);
        safePrice = priceOracle.getPriceInEth(WSETH_WETH_BAL_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function test_MavEthOracle() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_528_586);

        // Calculated - 1279055722000000000
        // Safe price - 1281595721753262897
        uint256 calculatedPrice = uint256(1_279_055_722_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(WSTETH_WETH_MAV);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    /**
     * @notice crvUsd / MIM and TricryptoLLAMA pool excluded as of 6/29/23.  MIM does not have a Chainlink price
     *      feed, and TricryptoLLAMA is a v2 ng pool.
     */
    function test_CurveStableSwapNGPools() external {
        // Pulled stEth ng pool test from elsewhere, use older fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_480_014);

        // Calculated - 1006028244000000000
        // Safe price - 1001718276876133469
        uint256 calculatedPrice = uint256(1_006_028_244_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(STETH_STABLESWAP_NG_POOL);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_586_413);

        // Set up here because pool did not exist at original setup fork.
        curveStableOracle.registerPool(SUSD_STABLESWAP_NG_POOL, SUSD_STABLESWAP_NG_POOL, false);

        // Calculated - 540613701000000
        // Safe price - 539414760524139;
        calculatedPrice = uint256(540_613_701_000_000);
        safePrice = priceOracle.getPriceInEth(USDC_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 540416370000000
        // Safe price - 540237542722259
        calculatedPrice = uint256(540_416_370_000_000);
        safePrice = priceOracle.getPriceInEth(USDT_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 539978431000000
        // Safe price - 538905372335699
        calculatedPrice = uint256(539_978_431_000_000);
        safePrice = priceOracle.getPriceInEth(TUSD_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 540443002000000
        // Safe price - 534720896910672
        calculatedPrice = uint256(540_443_002_000_000);
        safePrice = priceOracle.getPriceInEth(USDP_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 539914597000000
        // Safe price - 539944276470054
        calculatedPrice = uint256(539_914_597_000_000);
        safePrice = priceOracle.getPriceInEth(FRAX_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 539909058000000
        // Safe price - 538554606113206
        calculatedPrice = uint256(539_909_058_000_000);
        safePrice = priceOracle.getPriceInEth(SUSD_STABLESWAP_NG_POOL);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    /**
     * @notice Tested against multiple v2 pools that we are not using to test validity of approach.
     */
    function test_CurveV2Pools() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_672_343);

        // Calculated - 2079485290000000000
        // Safe price - 2077740002016828677
        uint256 calculatedPrice = uint256(2_079_485_290_000_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(RETH_ETH_CURVE_LP);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 42945287200000000
        // Safe Price - 43072642081141667
        calculatedPrice = uint256(42_945_287_200_000_000);
        safePrice = priceOracle.getPriceInEth(CRV_ETH_CURVE_V2_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Calculated - 64666948400000000
        // Safe price - 64695922392289196
        calculatedPrice = uint256(64_695_922_392_289_196);
        safePrice = priceOracle.getPriceInEth(LDO_ETH_CURVE_V2_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        //
        // Non-eth base tests.
        //
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_914_103);
        // Set up here, does not exist at block forked for `setUp()`.
        chainlinkOracle.registerChainlinkOracle(
            STG_MAINNET, IAggregatorV3Interface(STG_CL_FEED_MAINNET), BaseOracleDenominations.Denomination.USD, 24 hours
        );

        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        // Set frxEth pricing with custom set oracle, price in Eth taken from Coingecko.
        tokens[0] = FRXETH_MAINNET;
        prices[0] = 998_126_960_000_000_000;
        timestamps[0] = block.timestamp;
        customSetOracle.setPrices(tokens, prices, timestamps);

        // Safe price - 892992560872301
        // Calculated - 898924164000000
        calculatedPrice = uint256(898_924_164_000_000);
        safePrice = priceOracle.getPriceInEth(STG_USDC_CURVE_V2_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // Safe price - 284617745946998885
        // Calculated - 280364973000000000
        calculatedPrice = uint256(280_364_973_000_000_000);
        safePrice = priceOracle.getPriceInEth(WBTC_BADGER_CURVE_V2_LP);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    // Specifically test path when asset is priced in USD
    function test_EthInUsdPath() external {
        // Use bal usdc - usdt - dai pool, usdc denominated in USD

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_310);

        chainlinkOracle.removeChainlinkRegistration(USDC_MAINNET);
        chainlinkOracle.registerChainlinkOracle(
            USDC_MAINNET,
            IAggregatorV3Interface(USDC_IN_USD_CL_FEED_MAINNET),
            BaseOracleDenominations.Denomination.USD,
            24 hours
        );

        // calculated - 588167942000000
        // safe price - 587583813652788
        uint256 calculatedPrice = uint256(588_167_942_000_000);
        uint256 safePrice = priceOracle.getPriceInEth(THREE_CURVE_POOL_MAINNET_LP);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
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
        priceOracle.registerPoolMapping(RETH_WETH_BAL_POOL, balancerMetaOracle);
        priceOracle.registerPoolMapping(WSETH_WETH_BAL_POOL, balancerMetaOracle);

        priceOracle.registerPoolMapping(STETH_ETH_CURVE_POOL, curveStableOracle);
        priceOracle.registerPoolMapping(ST_ETH_CURVE_LP_TOKEN_MAINNET, curveStableOracle);
        priceOracle.registerPoolMapping(THREE_CURVE_MAINNET, curveStableOracle);
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
        curveStableOracle.registerPool(STETH_ETH_CURVE_POOL, ST_ETH_CURVE_LP_TOKEN_MAINNET, true);

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
        curveStableOracle.registerPool(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, true);

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
        curveStableOracle.registerPool(RETH_WSTETH_CURVE_POOL, RETH_WSTETH_CURVE_POOL_LP, true);

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
        curveStableOracle.registerPool(STETH_STABLESWAP_NG_POOL, STETH_STABLESWAP_NG_POOL, false);

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
        curveStableOracle.registerPool(USDC_STABLESWAP_NG_POOL, USDC_STABLESWAP_NG_POOL, false);

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
        curveStableOracle.registerPool(USDT_STABLESWAP_NG_POOL, USDT_STABLESWAP_NG_POOL, false);

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
        curveStableOracle.registerPool(TUSD_STABLESWAP_NG_POOL, TUSD_STABLESWAP_NG_POOL, false);

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
        curveStableOracle.registerPool(USDP_STABLESWAP_NG_POOL, USDP_STABLESWAP_NG_POOL, false);

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
        curveStableOracle.registerPool(FRAX_STABLESWAP_NG_POOL, FRAX_STABLESWAP_NG_POOL, false);

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
    function test_CurveV2Pools() external {
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

        chainlinkOracle.registerChainlinkOracle(
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

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 4, isSpotSafe);

        // Calculated USDC - 516.998617511
        calculatedPrice = uint256(516_998_617);
        (spotPrice, safePrice, isSpotSafe) =
            priceOracle.getRangePricesLP(WBTC_BADGER_CURVE_V2_LP, WBTC_BADGER_V2_POOL, USDC_MAINNET);

        _verifySafePriceByPercentTolerance(calculatedPrice, safePrice, spotPrice, 4, isSpotSafe);
    }

    function test_EthInUsdPath() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_475_310);

        chainlinkOracle.removeChainlinkRegistration(USDC_MAINNET);
        chainlinkOracle.registerChainlinkOracle(
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
}
