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
    STG_USDC_V2_POOL,
    STG_USDC_CURVE_V2_LP,
    CRV_MAINNET,
    WETH9_ADDRESS,
    RETH_WETH_CURVE_POOL,
    RETH_ETH_CURVE_LP,
    RETH_MAINNET
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

        registry = new SystemRegistry(address(1), address(2));

        accessControl = new AccessController(address(registry));
        registry.setAccessController(address(accessControl));

        oracle = new RootPriceOracle(registry);
        registry.setRootPriceOracle(address(oracle));

        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        curveOracle =
            new CurveV2CryptoEthOracle(ISystemRegistry(address(registry)), ICurveResolver(address(curveResolver)));
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
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);
    }

    function test_RevertZeroAddressCurvePool() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curvePool"));
        curveOracle.registerPool(address(0), CRV_ETH_CURVE_V2_LP, false);
    }

    function test_ZeroAddressLpTokenRegistration() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curveLpToken"));
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, address(0), false);
    }

    function test_LpTokenAlreadyRegistered() external {
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, CRV_ETH_CURVE_V2_POOL));
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);
    }

    function test_InvalidTokenNumber() external {
        vm.expectRevert(abi.encodeWithSelector(CurveV2CryptoEthOracle.InvalidNumTokens.selector, 3));
        curveOracle.registerPool(THREE_CURVE_MAINNET, CRV_ETH_CURVE_V2_LP, false);
    }

    function test_NotCryptoPool() external {
        vm.expectRevert(
            abi.encodeWithSelector(CurveV2CryptoEthOracle.NotCryptoPool.selector, STETH_WETH_CURVE_POOL_CONCENTRATED)
        );
        curveOracle.registerPool(STETH_WETH_CURVE_POOL_CONCENTRATED, CRV_ETH_CURVE_V2_LP, false);
    }

    function test_LpTokenMistmatch() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                CurveV2CryptoEthOracle.ResolverMismatch.selector, CVX_ETH_CURVE_V2_LP, CRV_ETH_CURVE_V2_LP
            )
        );
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CVX_ETH_CURVE_V2_LP, false);
    }

    function test_ProperRegistration() external {
        vm.expectEmit(false, false, false, true);
        emit TokenRegistered(CRV_ETH_CURVE_V2_LP);

        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);

        (address pool, uint8 reentrancy, address priceToken, address tokenFromPrice) =
            curveOracle.lpTokenToPool(CRV_ETH_CURVE_V2_LP);
        assertEq(pool, CRV_ETH_CURVE_V2_POOL);
        assertEq(reentrancy, 0);
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
        curveOracle.registerPool(CRV_ETH_CURVE_V2_POOL, CRV_ETH_CURVE_V2_LP, false);

        vm.expectEmit(false, false, false, true);
        emit TokenUnregistered(CRV_ETH_CURVE_V2_LP);

        curveOracle.unregister(CRV_ETH_CURVE_V2_LP);

        (address pool, uint8 reentrancy, address tokenToPrice, address tokenFromPrice) =
            curveOracle.lpTokenToPool(CRV_ETH_CURVE_V2_LP);
        assertEq(pool, address(0));
        assertEq(reentrancy, 0);
        assertEq(tokenToPrice, address(0));
        assertEq(tokenFromPrice, address(0));
        // Verify pool to lp token
        assertEq(address(0), curveOracle.poolToLpToken(CRV_ETH_CURVE_V2_POOL));
    }

    // getPriceInEth
    // Actual pricing return functionality tested in `RootPriceOracleIntegrationTest.sol`
    function test_RevertTokenZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        curveOracle.getPriceInEth(address(0));
    }

    function test_RevertTokenNotRegistered() external {
        vm.expectRevert(abi.encodeWithSelector(CurveV2CryptoEthOracle.NotRegistered.selector, CRV_ETH_CURVE_V2_LP));
        curveOracle.getPriceInEth(CRV_ETH_CURVE_V2_LP);
    }

    function testGetSpotPriceRevertIfPoolIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        curveOracle.getSpotPrice(RETH_MAINNET, address(0), WETH9_ADDRESS);
    }

    function testGetSpotPriceRethWeth() public {
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, true);

        (uint256 price, address quote) = curveOracle.getSpotPrice(RETH_MAINNET, RETH_WETH_CURVE_POOL, WETH9_ADDRESS);

        // Asking for WETH but getting USDC as WETH is not in the pool
        assertEq(quote, WETH9_ADDRESS);

        // Data at block 17_671_884
        // dy: 1076347103771414425
        // fee: 3531140
        // FEE_PRECISION: 10000000000
        // price: 1076727311259202406

        assertEq(price, 1_076_727_311_259_202_406);
    }

    function testGetSpotPriceWethReth() public {
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, true);

        (uint256 price, address quote) = curveOracle.getSpotPrice(WETH9_ADDRESS, RETH_WETH_CURVE_POOL, RETH_MAINNET);

        // Asking for WETH but getting USDC as WETH is not in the pool
        assertEq(quote, RETH_MAINNET);

        // Data at block 17_671_884
        // dy: 928409014372911276
        // fee: 3531140
        // FEE_PRECISION: 10000000000
        // price: 928736964397357484

        assertEq(price, 928_736_964_397_357_484);
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
        curveOracle.registerPool(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, true);

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            curveOracle.getSafeSpotPriceInfo(RETH_WETH_CURVE_POOL, RETH_ETH_CURVE_LP, WETH9_ADDRESS);

        assertEq(reserves.length, 2);
        assertEq(totalLPSupply, 4_463_086_556_894_704_039_754, "totalLPSupply invalid");
        assertEq(reserves[0].token, WETH9_ADDRESS);
        assertEq(reserves[0].reserveAmount, 4_349_952_278_063_931_733_845, "token1: wrong reserve amount");
        assertEq(reserves[0].rawSpotPrice, 928_736_964_397_357_484, "token1: spotPrice invalid");
        // TODO: quote token variance
        assertEq(reserves[1].token, RETH_MAINNET, "wrong token2");
        assertEq(reserves[1].reserveAmount, 4_572_227_874_589_066_847_253, "token2: wrong reserve amount");
        assertEq(reserves[1].rawSpotPrice, 1_076_727_311_259_202_406, "token2: spotPrice invalid");
        // TODO: quote token variance check
    }
}
