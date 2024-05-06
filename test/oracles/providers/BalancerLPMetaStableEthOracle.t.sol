// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import {
    BAL_VAULT,
    RETH_MAINNET,
    WETH_MAINNET,
    CBETH_MAINNET,
    WSTETH_MAINNET,
    CBETH_WSTETH_BAL_POOL,
    RETH_WETH_BAL_POOL
} from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase

contract BalancerLPMetaStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPMetaStableEthOracle internal oracle;

    event ReceivedPrice();

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_951);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPMetaStableEthOracle(systemRegistry, VAULT);
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

contract GetSpotPrice is BalancerLPMetaStableEthOracleTests {
    /// @dev rEth -> wEth at block 17_378_951 is 1073058978063340336.  This is accounting for scaling up by 1e3
    function test_getSpotPrice_withWETHQuote() public {
        (uint256 price, address quoteToken) = oracle.getSpotPrice(RETH_MAINNET, RETH_WETH_BAL_POOL, WETH_MAINNET);

        assertEq(quoteToken, WETH_MAINNET);
        assertEq(price, 1_073_058_978_063_340_336);
    }

    /// @dev wEth -> rEth at block 17_378_951 is 931915224161799719.  This is accounting for scaling up by 1e3.
    function test_getSpotPrice_withoutWETHQuote() public {
        (uint256 price, address quoteToken) = oracle.getSpotPrice(WETH_MAINNET, RETH_WETH_BAL_POOL, RETH_MAINNET);

        assertEq(quoteToken, RETH_MAINNET);
        assertEq(price, 931_915_224_161_799_719);
    }
}

contract GetSafeSpotPriceInfo is BalancerLPMetaStableEthOracleTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_getSafeSpotPrice_RevertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        oracle.getSafeSpotPriceInfo(address(0), RETH_WETH_BAL_POOL, WETH_MAINNET);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        oracle.getSafeSpotPriceInfo(RETH_WETH_BAL_POOL, address(0), WETH_MAINNET);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "quoteToken"));
        oracle.getSafeSpotPriceInfo(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, address(0));
    }

    function test_getSafeSpotPriceInfo_CbEthWstEthPool() public {
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(CBETH_WSTETH_BAL_POOL, CBETH_WSTETH_BAL_POOL, WETH_MAINNET);

        assertEq(reserves.length, 2, "rl");
        assertEq(totalLPSupply, 18_041_051_911_925_925_865_156, "lpSupply");
        assertEq(reserves[0].token, WSTETH_MAINNET, "zeroToken");
        assertEq(reserves[0].reserveAmount, 7_153_059_635_966_264_986_141, "zeroReserve");
        assertEq(reserves[0].rawSpotPrice, 1_089_652_135_532_585_034, "zeroRaw");
        assertEq(reserves[0].actualQuoteToken, CBETH_MAINNET, "zeroActual");
        assertEq(reserves[1].token, CBETH_MAINNET, "oneToken");
        assertEq(reserves[1].reserveAmount, 9_804_597_003_965_141_038_572, "oneReserve");
        assertEq(reserves[1].rawSpotPrice, 917_724_072_076_745_698, "oneRaw");
        assertEq(reserves[1].actualQuoteToken, WSTETH_MAINNET, "oneActual");
    }

    function test_getSafeSpotPriceInfo_RethWethPool() public {
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(RETH_WETH_BAL_POOL, RETH_WETH_BAL_POOL, WETH_MAINNET);

        assertEq(reserves.length, 2, "rl");
        assertEq(totalLPSupply, 41_458_365_247_894_236_652_969, "lpSupply");
        assertEq(reserves[0].token, RETH_MAINNET, "zeroToken");
        assertEq(reserves[0].reserveAmount, 19_543_079_911_395_563_931_751, "zeroReserve");
        assertEq(reserves[0].rawSpotPrice, 1_073_058_978_063_340_336, "zeroRaw");
        assertEq(reserves[0].actualQuoteToken, WETH_MAINNET, "zeroActual");
        assertEq(reserves[1].token, WETH_MAINNET, "oneToken");
        assertEq(reserves[1].reserveAmount, 21_445_519_175_513_497_135_889, "oneReserve");
        assertEq(reserves[1].rawSpotPrice, 931_915_224_161_799_719, "oneRaw");
        assertEq(reserves[1].actualQuoteToken, RETH_MAINNET, "oneActual");
    }

    function test_InvalidPoolReverts() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");
        vm.mockCall(mockPool, abi.encodeWithSelector(IBalancerMetaStablePool.getPoolId.selector), abi.encode(badPoolId));
        vm.mockCall(mockPool, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1));
        vm.expectRevert("BAL#500");
        oracle.getSafeSpotPriceInfo(mockPool, mockPool, WETH_MAINNET);
    }
}
