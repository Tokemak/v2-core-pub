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

    function setUp() external {
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

    //
    // Test Lp token pricing
    //
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

    // Test `getPriceInQuote()` individually.
    function test_GetPriceInQuote() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_021_563);

        // stEth in usdc
        // calculated - 1724550123000000000000
        // safe price - 1736857822983362723964
        uint256 calculatedPrice = uint256(1_724_550_123_000_000_000_000);
        uint256 safePrice = priceOracle.getPriceInQuote(STETH_MAINNET, USDC_MAINNET);
        (uint256 upperBound, uint256 lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);

        // usdt in crv
        // calculated - 2032995638000000000
        // safe price - 2017150178107977497
        calculatedPrice = uint256(2_032_995_638_000_000_000);
        safePrice = priceOracle.getPriceInQuote(USDT_MAINNET, CRV_MAINNET);
        (upperBound, lowerBound) = _getTwoPercentTolerance(calculatedPrice);
        assertGt(upperBound, safePrice);
        assertLt(lowerBound, safePrice);
    }

    function _getTwoPercentTolerance(uint256 price) internal pure returns (uint256 upperBound, uint256 lowerBound) {
        uint256 twoPercentToleranceValue = (price * 2) / 100;

        upperBound = price + twoPercentToleranceValue;
        lowerBound = price - twoPercentToleranceValue;
    }
}
