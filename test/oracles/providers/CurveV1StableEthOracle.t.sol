// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Vm } from "forge-std/Vm.sol";
import { Roles } from "src/libs/Roles.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IstEth } from "src/interfaces/external/lido/IstEth.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ICurveV1StableSwap } from "src/interfaces/external/curve/ICurveV1StableSwap.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { Errors } from "src/utils/Errors.sol";
import {
    STETH_ETH_CURVE_POOL,
    CURVE_META_REGISTRY_MAINNET,
    ST_ETH_CURVE_LP_TOKEN_MAINNET,
    STETH_MAINNET,
    CURVE_ETH,
    USDC_MAINNET,
    DAI_MAINNET,
    USDT_MAINNET,
    THREE_CURVE_POOL_MAINNET_LP,
    THREE_CURVE_MAINNET,
    STETH_STABLESWAP_NG_POOL,
    FRAX_USDC,
    FRAX_USDC_LP,
    FRAX_MAINNET,
    WETH9_ADDRESS,
    STETH_ETH_CURVE_POOL,
    ST_ETH_CURVE_LP_TOKEN_MAINNET,
    STETH_MAINNET
} from "test/utils/Addresses.sol";

contract CurveV1StableEthOracleTests is Test {
    address internal constant STETH_ETH_LP_TOKEN = ST_ETH_CURVE_LP_TOKEN_MAINNET;
    IstEth internal constant STETH_CONTRACT = IstEth(STETH_MAINNET);

    IRootPriceOracle internal rootPriceOracle;
    ISystemRegistry internal systemRegistry;
    AccessController internal accessController;
    CurveResolverMainnet internal curveResolver;
    CurveV1StableEthOracle internal oracle;

    event ReceivedPrice();

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_379_099);
        vm.selectFork(mainnetFork);

        systemRegistry = ISystemRegistry(vm.addr(327_849));
        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        accessController = new AccessController(address(systemRegistry));
        generateSystemRegistry(address(systemRegistry), address(accessController), address(rootPriceOracle));
        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        oracle = new CurveV1StableEthOracle(systemRegistry, curveResolver);

        // Ensure the onlyOwner call passes
        accessController.grantRole(0x00, address(this));
    }

    function testUnregisterSecurity() public {
        oracle.registerPool(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, false);

        address testUser1 = vm.addr(34_343);
        vm.prank(testUser1);

        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        oracle.unregister(THREE_CURVE_POOL_MAINNET_LP);
    }

    function testUnregisterMustExist() public {
        oracle.registerPool(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, false);

        address notRegisteredToken = vm.addr(33);
        vm.expectRevert(abi.encodeWithSelector(CurveV1StableEthOracle.NotRegistered.selector, notRegisteredToken));
        oracle.unregister(notRegisteredToken);
    }

    function testUnregister() public {
        oracle.registerPool(THREE_CURVE_MAINNET, THREE_CURVE_POOL_MAINNET_LP, true);

        address[] memory tokens = oracle.getLpTokenToUnderlying(THREE_CURVE_POOL_MAINNET_LP);
        (address pool, uint8 checkReentrancy) = oracle.lpTokenToPool(THREE_CURVE_POOL_MAINNET_LP);
        address poolToLpToken = oracle.poolToLpToken(THREE_CURVE_MAINNET);

        assertEq(tokens.length, 3);
        assertEq(tokens[0], DAI_MAINNET);
        assertEq(tokens[1], USDC_MAINNET);
        assertEq(tokens[2], USDT_MAINNET);
        assertEq(pool, THREE_CURVE_MAINNET);
        assertEq(checkReentrancy, 1);
        assertEq(poolToLpToken, THREE_CURVE_POOL_MAINNET_LP);

        oracle.unregister(THREE_CURVE_POOL_MAINNET_LP);

        address[] memory afterTokens = oracle.getLpTokenToUnderlying(THREE_CURVE_POOL_MAINNET_LP);
        (address afterPool, uint8 afterCheckReentrancy) = oracle.lpTokenToPool(THREE_CURVE_POOL_MAINNET_LP);
        address afterPoolToLpToken = oracle.poolToLpToken(THREE_CURVE_MAINNET);

        assertEq(afterTokens.length, 0);
        assertEq(afterPool, address(0));
        assertEq(afterCheckReentrancy, 0);
        assertEq(afterPoolToLpToken, address(0));
    }

    function testRegistrationSecurity() public {
        address mockPool = vm.addr(25);
        address matchingLP = vm.addr(26);

        address testUser1 = vm.addr(34_343);
        vm.prank(testUser1);

        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        oracle.registerPool(mockPool, matchingLP, true);
    }

    function testPoolRegistration() public {
        address mockResolver = vm.addr(24);
        address mockPool = vm.addr(25);
        address matchingLP = vm.addr(26);
        address nonMatchingLP = vm.addr(27);

        address[8] memory tokens;

        // Not stable swap
        vm.mockCall(
            mockResolver,
            abi.encodeWithSelector(CurveResolverMainnet.resolveWithLpToken.selector, mockPool),
            abi.encode(tokens, 0, matchingLP, false)
        );

        CurveV1StableEthOracle localOracle =
            new CurveV1StableEthOracle(systemRegistry, CurveResolverMainnet(mockResolver));

        vm.expectRevert(abi.encodeWithSelector(CurveV1StableEthOracle.NotStableSwap.selector, mockPool));
        localOracle.registerPool(mockPool, matchingLP, true);

        // stable swap but not matching
        vm.mockCall(
            mockResolver,
            abi.encodeWithSelector(CurveResolverMainnet.resolveWithLpToken.selector, mockPool),
            abi.encode(tokens, 0, nonMatchingLP, true)
        );

        vm.expectRevert(
            abi.encodeWithSelector(CurveV1StableEthOracle.ResolverMismatch.selector, matchingLP, nonMatchingLP)
        );
        localOracle.registerPool(mockPool, matchingLP, true);
    }

    function testGetSpotPriceRevertIfPoolIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        oracle.getSpotPrice(FRAX_MAINNET, address(0), WETH9_ADDRESS);
    }

    function testGetSpotPriceFraxUsdc() public {
        oracle.registerPool(FRAX_USDC, FRAX_USDC_LP, true);

        (uint256 price, address quote) = oracle.getSpotPrice(FRAX_MAINNET, FRAX_USDC, WETH9_ADDRESS);

        // Asking for WETH but getting USDC as WETH is not in the pool
        assertEq(quote, USDC_MAINNET);

        // Data at block 17_379_099
        // dy: 999187
        // fee: 1000000
        // FEE_PRECISION: 10000000000
        // price: 999286

        assertEq(price, 999_286);
    }

    function testGetSpotPriceUsdcFrax() public {
        oracle.registerPool(FRAX_USDC, FRAX_USDC_LP, true);

        (uint256 price, address quote) = oracle.getSpotPrice(USDC_MAINNET, FRAX_USDC, FRAX_MAINNET);

        assertEq(quote, FRAX_MAINNET);

        // Data at block 17_379_099
        // dy: 1000613407288920551
        // fee: 1000000
        // FEE_PRECISION: 10000000000
        // price: 1000713478636784229

        assertEq(price, 1_000_713_478_636_784_229);
    }

    // Testing fix for bug involving Eth being submitted as `address token` param on `getSpotPrice()`
    function testGetSpotPriceWorksWithEthAsToken() external {
        oracle.registerPool(STETH_ETH_CURVE_POOL, ST_ETH_CURVE_LP_TOKEN_MAINNET, false);

        (uint256 price, address actualQuote) = oracle.getSpotPrice(CURVE_ETH, STETH_ETH_CURVE_POOL, STETH_MAINNET);

        // Data at block 17_379_099
        // dy: 1000032797037899490
        // fee: 4000000
        // FEE_PRECISION: 1e10
        // price: 1000432970225989885

        assertEq(price, 1_000_432_970_225_989_885);
        assertEq(actualQuote, STETH_MAINNET);
    }

    function testGetSafeSpotPriceRevertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        oracle.getSafeSpotPriceInfo(address(0), FRAX_USDC_LP, WETH9_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        oracle.getSafeSpotPriceInfo(FRAX_USDC, address(0), WETH9_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "quoteToken"));
        oracle.getSafeSpotPriceInfo(FRAX_USDC, FRAX_USDC_LP, address(0));
    }

    function testGetSafeSpotPriceInfo() public {
        oracle.registerPool(FRAX_USDC, FRAX_USDC_LP, true);

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(FRAX_USDC, FRAX_USDC_LP, WETH9_ADDRESS);

        assertEq(reserves.length, 2);
        assertEq(totalLPSupply, 497_913_419_719_209_769_318_641_923);
        assertEq(reserves[0].token, FRAX_MAINNET, "wrong token1");
        assertEq(reserves[0].reserveAmount, 345_763_079_333_760_512_920_948_527, "token1: invalid reserve amount");
        assertEq(reserves[0].rawSpotPrice, 999_286, "token1: invalid spot price");
        assertEq(reserves[1].token, USDC_MAINNET, "wrong token2");
        assertEq(reserves[1].reserveAmount, 152_789_951_049_354, "token2: invalid reserve amount");
        assertEq(reserves[1].rawSpotPrice, 1_000_713_478_636_784_229, "token2: invalid spot price");
    }

    function mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function generateSystemRegistry(
        address registry,
        address accessControl,
        address rootOracle
    ) internal returns (ISystemRegistry) {
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));

        vm.mockCall(
            registry, abi.encodeWithSelector(ISystemRegistry.accessController.selector), abi.encode(accessControl)
        );

        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.weth.selector), abi.encode(IWETH9(WETH9_ADDRESS)));

        return ISystemRegistry(registry);
    }
}
