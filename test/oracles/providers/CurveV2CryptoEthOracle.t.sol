// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase
import { Test } from "forge-std/Test.sol";

import {
    CURVE_META_REGISTRY_MAINNET,
    CRV_ETH_CURVE_V2_LP,
    CRV_ETH_CURVE_V2_POOL,
    THREE_CURVE_MAINNET,
    STETH_WETH_CURVE_POOL_CONCENTRATED,
    CVX_ETH_CURVE_V2_LP,
    CRV_MAINNET,
    WETH9_ADDRESS,
    RETH_WETH_CURVE_POOL,
    RETH_ETH_CURVE_LP,
    RETH_MAINNET,
    CURVE_ETH,
    CBETH_ETH_V2_POOL,
    CBETH_ETH_V2_POOL_LP,
    CBETH_MAINNET
} from "test/utils/Addresses.sol";

import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

contract CurveV2CryptoEthOracleTest is Test {
    SystemRegistry public registry;
    AccessController public accessControl;
    RootPriceOracle public oracle;

    CurveResolverMainnet public curveResolver;
    CurveV2CryptoEthOracle public curveOracle;

    event TokenRegistered(address lpToken);
    event TokenUnregistered(address lpToken);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_671_884);

        registry = new SystemRegistry(address(1), WETH9_ADDRESS);

        accessControl = new AccessController(address(registry));
        registry.setAccessController(address(accessControl));

        oracle = new RootPriceOracle(registry);
        registry.setRootPriceOracle(address(oracle));

        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        curveOracle =
            new CurveV2CryptoEthOracle(ISystemRegistry(address(registry)), ICurveResolver(address(curveResolver)));

        accessControl.grantRole(Roles.ORACLE_MANAGER, address(this));
    }

    // Constructor
    function test_RevertRootPriceOracleZeroAddress() external {
        SystemRegistry localRegistry = new SystemRegistry(address(1), address(2));
        AccessController localAccessControl = new AccessController(address(localRegistry));
        localRegistry.setAccessController(address(localAccessControl));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rootPriceOracle"));
        new CurveV2CryptoEthOracle(localRegistry, curveResolver);
    }

    function test_RevertCurveResolverAddressZero() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_curveResolver"));
        new CurveV2CryptoEthOracle(registry, ICurveResolver(address(0)));
    }

    function test_ProperlySetsState() external {
        assertEq(address(curveOracle.curveResolver()), address(curveResolver));
    }

    // Register
    function test_RevertNonOwnerRegister() external {
        vm.prank(address(1));
        vm.expectRevert(Errors.AccessDenied.selector);
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP);
    }

    function test_RevertZeroAddressCurvePool() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curvePool"));
        curveOracle.registerPool(address(0), CRV_ETH_CURVE_V2_LP);
    }

    function test_ZeroAddressLpTokenRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curveLpToken"));
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, address(0));
    }

    function test_LpTokenAlreadyRegistered() external {
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, CRV_ETH_CURVE_V2_POOL));
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP);
    }

    function test_InvalidTokenNumber() external {
        vm.expectRevert(abi.encodeWithSelector(CurveV2CryptoEthOracle.InvalidNumTokens.selector, 3));
        curveOracle.registerPool(THREE_CURVE_MAINNET, CRV_ETH_CURVE_V2_LP);
    }

    function test_NotCryptoPool() external {
        vm.expectRevert(
            abi.encodeWithSelector(CurveV2CryptoEthOracle.NotCryptoPool.selector, STETH_WETH_CURVE_POOL_CONCENTRATED)
        );
        curveOracle.registerPool(STETH_WETH_CURVE_POOL_CONCENTRATED, CRV_ETH_CURVE_V2_LP);
    }

    function test_LpTokenMistmatch() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                CurveV2CryptoEthOracle.ResolverMismatch.selector, CVX_ETH_CURVE_V2_LP, CRV_ETH_CURVE_V2_LP
            )
        );
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CVX_ETH_CURVE_V2_LP);
    }

    function test_ProperRegistration() external {
        vm.expectEmit(false, false, false, true);
        emit TokenRegistered(CRV_ETH_CURVE_V2_LP);

        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP);

        (address pool, address priceToken, address tokenFromPrice) = curveOracle.lpTokenToPool(CRV_ETH_CURVE_V2_LP);
        assertEq(pool, CRV_ETH_CURVE_V2_POOL);
        assertEq(priceToken, CRV_MAINNET);
        assertEq(tokenFromPrice, WETH9_ADDRESS);
        // Verify pool to lp token
        assertEq(CRV_ETH_CURVE_V2_LP, curveOracle.poolToLpToken(CRV_ETH_CURVE_V2_POOL));
    }

    // Unregister
    function test_RevertNonOwnerUnRegister() external {
        vm.prank(address(1));
        vm.expectRevert(Errors.AccessDenied.selector);
        curveOracle.unregister(CRV_ETH_CURVE_V2_LP);
    }

    function test_RevertZeroAddressUnRegister() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curveLpToken"));
        curveOracle.unregister(address(0));
    }

    function test_LpNotRegistered() external {
        vm.expectRevert(abi.encodeWithSelector(CurveV2CryptoEthOracle.NotRegistered.selector, CRV_ETH_CURVE_V2_LP));
        curveOracle.unregister(CRV_ETH_CURVE_V2_LP);
    }

    function test_ProperUnRegister() external {
        // Register first
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP);

        vm.expectEmit(false, false, false, true);
        emit TokenUnregistered(CRV_ETH_CURVE_V2_LP);

        curveOracle.unregister(CRV_ETH_CURVE_V2_LP);

        (address pool, address tokenToPrice, address tokenFromPrice) = curveOracle.lpTokenToPool(CRV_ETH_CURVE_V2_LP);
        assertEq(pool, address(0));
        assertEq(tokenToPrice, address(0));
        assertEq(tokenFromPrice, address(0));
        // Verify pool to lp token
        assertEq(address(0), curveOracle.poolToLpToken(CRV_ETH_CURVE_V2_POOL));
    }

    function testGetSpotPriceRevertIfPoolIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        curveOracle.getSpotPrice(RETH_MAINNET, address(0), WETH9_ADDRESS);
    }

    function testGetSpotPriceRethWeth() public {
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP);

        (uint256 price, address quote) = curveOracle.getSpotPrice(RETH_MAINNET, RETH_WETH_CURVE_POOL, WETH9_ADDRESS);

        // Asking for WETH but getting USDC as WETH is not in the pool
        assertEq(quote, WETH9_ADDRESS);

        // Data at block 17_671_884
        // dy: 1076349492658479000
        // fee: 3531140
        // FEE_PRECISION: 10000000000
        // price: 1076729700990114423

        assertEq(price, 1_076_729_700_990_114_423);
    }

    function testGetSpotPriceWethReth() public {
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP);

        (uint256 price, address quote) = curveOracle.getSpotPrice(WETH9_ADDRESS, RETH_WETH_CURVE_POOL, RETH_MAINNET);

        // Asking for WETH but getting USDC as WETH is not in the pool
        assertEq(quote, RETH_MAINNET);

        // Data at block 17_671_884
        // dy: 928410242202755000
        // fee: 3531140
        // FEE_PRECISION: 10000000000
        // price: 928738192660918267

        assertEq(price, 928_738_192_660_918_267);
    }

    // Tests edge case where Eth is submitted as `address token`.
    function testGetSpotPriceEthCbEth() public {
        curveOracle.registerPool(CBETH_ETH_V2_POOL, CBETH_ETH_V2_POOL_LP);

        (uint256 price, address quote) = curveOracle.getSpotPrice(CURVE_ETH, CBETH_ETH_V2_POOL, CBETH_MAINNET);

        assertEq(quote, CBETH_MAINNET);

        // Data at block 17_671_884
        // dy: 957435338422750000
        // fee: 6113197
        // FEE_PRECISION: 10000000000
        // price: 958020995530331303

        assertEq(price, 958_020_995_530_331_303);
    }

    function testGetSpotPriceCbEthEth() public {
        curveOracle.registerPool(CBETH_ETH_V2_POOL, CBETH_ETH_V2_POOL_LP);

        (uint256 price, address quote) = curveOracle.getSpotPrice(CBETH_MAINNET, CBETH_ETH_V2_POOL, WETH9_ADDRESS);

        assertEq(quote, WETH9_ADDRESS);

        // Data at block 17_671_884
        // dy: 1043180213356946000
        // fee: 6113197
        // FEE_PRECISION: 10000000000
        // price: 1043818320059219105

        assertEq(price, 1_043_818_320_059_219_105);
    }

    function tesSpotPriceRevertIfNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(CurveV2CryptoEthOracle.NotRegistered.selector, RETH_ETH_CURVE_LP));
        curveOracle.getSpotPrice(RETH_MAINNET, RETH_WETH_CURVE_POOL, WETH9_ADDRESS);
    }

    function testGetSafeSpotPriceRevertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        curveOracle.getSafeSpotPriceInfo(address(0), RETH_ETH_CURVE_LP, WETH9_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        curveOracle.getSafeSpotPriceInfo(RETH_WETH_CURVE_POOL, address(0), WETH9_ADDRESS);
    }

    function testGetSafeSpotPriceInfo() public {
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP);

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            curveOracle.getSafeSpotPriceInfo(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, WETH9_ADDRESS);

        assertEq(reserves.length, 2);
        assertEq(totalLPSupply, 4_463_086_556_894_704_039_754, "totalLPSupply invalid");
        assertEq(reserves[0].token, WETH9_ADDRESS);
        assertEq(reserves[0].reserveAmount, 4_349_952_278_063_931_733_845, "token1: wrong reserve amount");
        assertEq(reserves[0].rawSpotPrice, 928_738_192_660_918_267, "token1: spotPrice invalid");
        // TODO: quote token variance
        assertEq(reserves[1].token, RETH_MAINNET, "wrong token2");
        assertEq(reserves[1].reserveAmount, 4_572_227_874_589_066_847_253, "token2: wrong reserve amount");
        assertEq(reserves[1].rawSpotPrice, 1_076_729_700_990_114_423, "token2: spotPrice invalid");
        // TODO: quote token variance check
    }
}
