// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { AerodromeOracle } from "src/oracles/providers/base/AerodromeOracle.sol";

import { SystemRegistry, ISystemRegistry } from "src/SystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Errors } from "src/utils/Errors.sol";
import {
    TOKE_MAINNET,
    WETH9_BASE,
    USDC_BASE,
    DAI_BASE,
    AERODROME_SWAP_ROUTER_BASE,
    RANDOM,
    AERO_BASE
} from "test/utils/Addresses.sol";
import { IRouter } from "src/interfaces/external/aerodrome/IRouter.sol";

// solhint-disable func-name-mixedcase
contract AerodromeOracleTest is Test {
    SystemRegistry public registry;
    AccessController public accessControl;
    RootPriceOracle public rootOracle;
    AerodromeOracle public aerodromeOracle;

    function setUp() external {
        uint256 baseFork = vm.createFork(vm.envString("BASE_MAINNET_RPC_URL"), 15_020_800);
        vm.selectFork(baseFork);
        _setUp();
    }

    function _setUp() internal {
        registry = new SystemRegistry(TOKE_MAINNET, WETH9_BASE);
        accessControl = new AccessController(address(registry));
        registry.setAccessController(address(accessControl));
        rootOracle = new RootPriceOracle(registry);
        registry.setRootPriceOracle(address(rootOracle));
        aerodromeOracle = new AerodromeOracle(registry);
    }

    // Constructor tests
    function test_RevertSystemRegistryZeroAddress() external {
        // Reverts with generic evm revert.
        vm.expectRevert();
        aerodromeOracle = new AerodromeOracle(ISystemRegistry(address(0)));
    }

    function test_RevertZeroAddressGetSpotPrice() external {
        address token = DAI_BASE;
        address quoteToken = USDC_BASE;

        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            token, quoteToken, true, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );

        //set token to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        (uint256 price, address actualQuoteToken) = aerodromeOracle.getSpotPrice(address(0), pool, quoteToken);

        // set pool to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        (price, actualQuoteToken) = aerodromeOracle.getSpotPrice(token, address(0), quoteToken);
    }

    function test_RevertInvalidPoolGetSpotPrice() external {
        address token = DAI_BASE;
        address quoteToken = USDC_BASE;

        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            token, quoteToken, true, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );

        //pass RANDOM_ADDRESS as token
        vm.expectRevert(abi.encodeWithSelector(AerodromeOracle.InvalidPool.selector, pool));
        aerodromeOracle.getSpotPrice(RANDOM, pool, quoteToken);
    }

    function test_GetSpotPrice_DAIUSDC() external {
        address token = DAI_BASE;
        address quoteToken = USDC_BASE;

        uint256 expectedPrice = 999_499;

        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            token, quoteToken, true, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );
        (uint256 price, address actualQuoteToken) = aerodromeOracle.getSpotPrice(token, pool, quoteToken);

        assertEq(price, expectedPrice);
        assertEq(actualQuoteToken, quoteToken);
    }

    function test_RevertZeroAddressGetSafeSpotPriceInfo() external {
        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            DAI_BASE, USDC_BASE, true, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );

        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](2);
        uint256 totalLPSupply;

        //set pool to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        (totalLPSupply, reserves) = aerodromeOracle.getSafeSpotPriceInfo(address(0x0), pool, address(0x0));

        //set pool to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        (totalLPSupply, reserves) = aerodromeOracle.getSafeSpotPriceInfo(pool, address(0x0), address(0x0));
    }

    function test_GetSafeSpotPriceInfo() external {
        uint256 expectedTotalLPSuppy = 272_649_082_263_574_351;

        uint256 daiReserveAmount = 284_994_962_665_608_427_910_568;
        uint256 daiSpotPrice = 999_499;

        uint256 usdcReserveAmount = 260_363_464_866;
        uint256 usdcSpotPrice = 1_000_184_287_492_292_946;

        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            DAI_BASE, USDC_BASE, true, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );

        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](2);

        uint256 totalLPSupply;
        (totalLPSupply, reserves) = aerodromeOracle.getSafeSpotPriceInfo(pool, pool, address(0x0));

        assertEq(totalLPSupply, expectedTotalLPSuppy);
        assertEq(reserves.length, 2);

        assertEq(reserves[0].token, DAI_BASE);
        assertEq(reserves[0].reserveAmount, daiReserveAmount);
        assertEq(reserves[0].rawSpotPrice, daiSpotPrice);
        assertEq(reserves[0].actualQuoteToken, USDC_BASE);

        assertEq(reserves[1].token, USDC_BASE);
        assertEq(reserves[1].reserveAmount, usdcReserveAmount);
        assertEq(reserves[1].rawSpotPrice, usdcSpotPrice);
        assertEq(reserves[1].actualQuoteToken, DAI_BASE);
    }

    function test_GetSafeSpotPriceInfoPoolUnstable() external {
        uint256 expectedTotalLPSuppy = 811_833_624_258_001_511;

        uint256 usdcReserveAmount = 49_494_627_388_233;
        uint256 usdcSpotPrice = 813_309_660_819_200_606;

        uint256 aeroReserveAmount = 40_254_458_621_548_265_837_771_539;
        uint256 aeroSpotPrice = 1_229_292;

        address pool = IRouter(AERODROME_SWAP_ROUTER_BASE).poolFor(
            AERO_BASE, USDC_BASE, false, IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        );

        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](2);

        uint256 totalLPSupply;
        (totalLPSupply, reserves) = aerodromeOracle.getSafeSpotPriceInfo(pool, pool, address(0x0));

        assertEq(totalLPSupply, expectedTotalLPSuppy);
        assertEq(reserves.length, 2);

        assertEq(reserves[0].token, USDC_BASE);
        assertEq(reserves[0].reserveAmount, usdcReserveAmount);
        assertEq(reserves[0].rawSpotPrice, usdcSpotPrice);
        assertEq(reserves[0].actualQuoteToken, AERO_BASE);

        assertEq(reserves[1].token, AERO_BASE);
        assertEq(reserves[1].reserveAmount, aeroReserveAmount);
        assertEq(reserves[1].rawSpotPrice, aeroSpotPrice);
        assertEq(reserves[1].actualQuoteToken, USDC_BASE);
    }
}
