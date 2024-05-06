// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import {
    WETH_MAINNET,
    DAI_MAINNET,
    USDT_MAINNET,
    USDC_MAINNET,
    BAL_VAULT,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SFRXETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerLPComposableStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPComposableStableEthOracle internal oracle;

    uint256 private mainnetFork;

    function setUp() public virtual {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_951);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPComposableStableEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}

contract GetSpotPrice is BalancerLPComposableStableEthOracleTests {
    /// @dev rEth -> sfrxETH at block 17_378_951 is 1029088775280746000.  This is accounting for scaling up by 1e3
    /// Pool has no WETH so it returns sfrxETH
    function test_getSpotPrice_withWETHQuote() public {
        (uint256 price, address quoteToken) =
            oracle.getSpotPrice(RETH_MAINNET, WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET);

        assertEq(quoteToken, SFRXETH_MAINNET);
        assertEq(price, 1_029_500_575_510_950_380);
    }

    /// @dev rEth -> wstETH at block 17_378_951 is 952138412066946000.  This is accounting for scaling up by 1e3.
    function test_getSpotPrice_withoutWETHQuote() public {
        (uint256 price, address quoteToken) = oracle.getSpotPrice(
            RETH_MAINNET, // rEth
            WSETH_RETH_SFRXETH_BAL_POOL,
            WSTETH_MAINNET // wstETH
        );

        assertEq(quoteToken, WSTETH_MAINNET);
        assertEq(price, 952_519_419_834_879_951);
    }
}

contract GetSafeSpotPriceInfo is BalancerLPComposableStableEthOracleTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_getSafeSpotPrice_RevertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        oracle.getSafeSpotPriceInfo(address(0), WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        oracle.getSafeSpotPriceInfo(WSETH_RETH_SFRXETH_BAL_POOL, address(0), WETH_MAINNET);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "quoteToken"));
        oracle.getSafeSpotPriceInfo(WSETH_RETH_SFRXETH_BAL_POOL, WSETH_RETH_SFRXETH_BAL_POOL, address(0));
    }

    function test_getSafeSpotPriceInfo() public {
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(WSETH_RETH_SFRXETH_BAL_POOL, WSETH_RETH_SFRXETH_BAL_POOL, WETH_MAINNET);

        assertEq(reserves.length, 3);
        assertEq(totalLPSupply, 22_960_477_413_652_244_357_906);
        assertEq(reserves[0].token, WSTETH_MAINNET);
        assertEq(reserves[0].reserveAmount, 7_066_792_475_374_351_999_170);
        assertEq(reserves[0].rawSpotPrice, 1_049_847_360_256_655_662);
        assertEq(reserves[0].actualQuoteToken, RETH_MAINNET);
        assertEq(reserves[1].token, SFRXETH_MAINNET);
        assertEq(reserves[1].reserveAmount, 7_687_228_718_047_274_083_418);
        assertEq(reserves[1].rawSpotPrice, 971_344_768_870_315_126);
        assertEq(reserves[1].actualQuoteToken, RETH_MAINNET);
        assertEq(reserves[2].token, RETH_MAINNET);
        assertEq(reserves[2].reserveAmount, 6_722_248_966_013_056_226_285);
        assertEq(reserves[2].rawSpotPrice, 1_029_500_575_510_950_380);
        assertEq(reserves[2].actualQuoteToken, SFRXETH_MAINNET);
    }

    function test_getSafeSpotPriceInfo_UsdBasedPool() public {
        address USDC_DAI_USDT_COMPOSABLE = 0x79c58f70905F734641735BC61e45c19dD9Ad60bC;

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(USDC_DAI_USDT_COMPOSABLE, USDC_DAI_USDT_COMPOSABLE, WETH_MAINNET);

        assertEq(reserves.length, 3, "rl");
        assertEq(totalLPSupply, 4_351_658_079_624_087_001_833_240, "lpSupply");
        assertEq(reserves[0].token, DAI_MAINNET, "zeroToken");
        assertEq(reserves[0].reserveAmount, 1_763_357_455_402_916_823_249_116, "zeroReserve");
        assertEq(reserves[0].rawSpotPrice, 999_049, "zeroRaw");
        assertEq(reserves[0].actualQuoteToken, USDT_MAINNET, "zeroActual");
        assertEq(reserves[1].token, USDC_MAINNET, "oneToken");
        assertEq(reserves[1].reserveAmount, 1_644_631_949_309, "oneReserve");
        assertEq(reserves[1].rawSpotPrice, 998_049, "oneRaw");
        assertEq(reserves[1].actualQuoteToken, USDT_MAINNET, "oneActual");
        assertEq(reserves[2].token, USDT_MAINNET, "twoToken");
        assertEq(reserves[2].reserveAmount, 946_215_901_433, "twoReserve");
        assertEq(reserves[2].rawSpotPrice, 999_049, "twoRaw");
        assertEq(reserves[2].actualQuoteToken, USDC_MAINNET, "twoActual");
    }

    function test_InvalidPoolReverts() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");
        vm.mockCall(
            mockPool, abi.encodeWithSelector(IBalancerComposableStablePool.getPoolId.selector), abi.encode(badPoolId)
        );
        vm.mockCall(mockPool, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1));
        vm.expectRevert();
        oracle.getSafeSpotPriceInfo(mockPool, mockPool, WETH_MAINNET);
    }
}
