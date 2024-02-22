// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { IwstEth } from "src/interfaces/external/lido/IwstEth.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { RootPriceOracle, IRootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";

contract RootPriceOracleTests is Test {
    SystemRegistry internal _systemRegistry;
    AccessController private _accessController;
    RootPriceOracle internal _rootPriceOracle;

    address internal _pool;
    address internal _token;
    address internal _poolOracle;
    address internal _tokenOracle;
    address internal _actualToken;
    uint256 internal actualTokenDecimals = 6;

    event PoolRegistered(address indexed pool, address indexed oracle);
    event PoolRegistrationReplaced(address indexed pool, address indexed oldOracle, address indexed newOracle);
    event PoolRemoved(address indexed pool);
    event SafeSpotPriceThresholdUpdated(address token, uint256 threshold);

    error AlreadyRegistered(address token);
    error MissingTokenOracle(address token);
    error MappingDoesNotExist(address token);
    error ReplaceOldMismatch(address token, address oldExpected, address oldActual);
    error ReplaceAlreadyMatches(address token, address newOracle);

    function setUp() public virtual {
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));
        _rootPriceOracle = new RootPriceOracle(_systemRegistry);

        _pool = makeAddr("_pool");
        _token = makeAddr("_token");
        _poolOracle = makeAddr("_poolOracle");
        _tokenOracle = makeAddr("_tokenOracle");
        _actualToken = makeAddr("_actualToken");
    }

    function testConstruction() public {
        vm.expectRevert();
        new RootPriceOracle(SystemRegistry(address(0)));

        assertEq(address(_rootPriceOracle.getSystemRegistry()), address(_systemRegistry));
    }

    function testRegisterMappingParamValidation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _rootPriceOracle.registerMapping(address(0), IPriceOracle(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oracle"));
        _rootPriceOracle.registerMapping(vm.addr(23), IPriceOracle(address(0)));

        address badRegistry = vm.addr(888);
        address badOracle = vm.addr(999);
        mockSystemComponent(badOracle, badRegistry);
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_rootPriceOracle), badOracle));
        _rootPriceOracle.registerMapping(vm.addr(23), IPriceOracle(badOracle));
    }

    function testReplacingAttemptOnRegister() public {
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(vm.addr(23), IPriceOracle(oracle));

        address newOracle = vm.addr(9996);
        mockSystemComponent(newOracle, address(_systemRegistry));
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.AlreadyRegistered.selector, vm.addr(23)));
        _rootPriceOracle.registerMapping(vm.addr(23), IPriceOracle(newOracle));
    }

    function testSuccessfulRegister() public {
        address token = vm.addr(5);
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        assertEq(address(_rootPriceOracle.tokenMappings(token)), oracle);
    }

    function testReplacingParamValidation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _rootPriceOracle.replaceMapping(address(0), IPriceOracle(address(0)), IPriceOracle(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oldOracle"));
        _rootPriceOracle.replaceMapping(vm.addr(23), IPriceOracle(address(0)), IPriceOracle(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newOracle"));
        _rootPriceOracle.replaceMapping(vm.addr(23), IPriceOracle(vm.addr(23)), IPriceOracle(address(0)));

        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(vm.addr(333)));
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_rootPriceOracle), oracle));
        _rootPriceOracle.replaceMapping(vm.addr(23), IPriceOracle(vm.addr(23)), IPriceOracle(oracle));
    }

    function testReplaceMustMatchOld() public {
        address token = vm.addr(5);
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        address newOracle = vm.addr(9998);
        mockSystemComponent(newOracle, address(_systemRegistry));
        address badOld = vm.addr(5454);
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.ReplaceOldMismatch.selector, token, badOld, oracle));
        _rootPriceOracle.replaceMapping(token, IPriceOracle(badOld), IPriceOracle(newOracle));
    }

    function testReplaceMustBeNew() public {
        address token = vm.addr(5);
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.ReplaceAlreadyMatches.selector, token, oracle));
        _rootPriceOracle.replaceMapping(token, IPriceOracle(oracle), IPriceOracle(oracle));
    }

    function testReplaceIsSet() public {
        address token = vm.addr(5);
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        address newOracle = vm.addr(9998);
        mockSystemComponent(newOracle, address(_systemRegistry));
        _rootPriceOracle.replaceMapping(token, IPriceOracle(oracle), IPriceOracle(newOracle));

        assertEq(address(_rootPriceOracle.tokenMappings(token)), newOracle);
    }

    function testRemoveParamValidation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _rootPriceOracle.replaceMapping(address(0), IPriceOracle(address(0)), IPriceOracle(address(0)));
    }

    function testRemoveChecksIsSet() public {
        address token = vm.addr(5);

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MappingDoesNotExist.selector, token));
        _rootPriceOracle.removeMapping(token);
    }

    function testRemoveDeletes() public {
        address token = vm.addr(5);
        address oracle = vm.addr(999);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        _rootPriceOracle.removeMapping(token);

        assertEq(address(_rootPriceOracle.tokenMappings(token)), address(0));
    }

    function testRegisterMappingSecurity() public {
        address testUser1 = vm.addr(34_343);
        vm.prank(testUser1);

        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        _rootPriceOracle.registerMapping(vm.addr(23), IPriceOracle(vm.addr(4444)));
    }

    function testReplacerMappingSecurity() public {
        address testUser1 = vm.addr(34_343);
        vm.prank(testUser1);

        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));

        _rootPriceOracle.replaceMapping(vm.addr(23), IPriceOracle(vm.addr(4444)), IPriceOracle(vm.addr(4444)));
    }

    function testRemoveMappingSecurity() public {
        address testUser1 = vm.addr(34_343);
        vm.prank(testUser1);

        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        _rootPriceOracle.removeMapping(vm.addr(23));
    }

    function testRegisterAndResolve() public {
        address oracle = vm.addr(44_444);
        address token = vm.addr(55);
        mockOracle(oracle, token, 5e18);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        uint256 price = _rootPriceOracle.getPriceInEth(token);

        assertEq(price, 5e18);
    }

    function testResolveBailsIfNotRegistered() public {
        address oracle = vm.addr(44_444);
        address token = vm.addr(55);
        mockOracle(oracle, token, 5e18);
        mockSystemComponent(oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(token, IPriceOracle(oracle));

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingTokenOracle.selector, vm.addr(44)));
        _rootPriceOracle.getPriceInEth(vm.addr(44));
    }

    function mockOracle(address oracle, address token, uint256 price) internal {
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IPriceOracle.getPriceInEth.selector, token), abi.encode(price)
        );
    }

    function mockSystemComponent(address component, address system) internal {
        vm.mockCall(component, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(system));
    }
}

contract RegisterPoolMapping is RootPriceOracleTests {
    function test_RevertsIfPoolAddressIsZero() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        _rootPriceOracle.registerPoolMapping(address(0), ISpotPriceOracle(_poolOracle));
    }

    function test_RevertsIfOracleAddressIsZero() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oracle"));
        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(address(0)));
    }

    function test_RevertsIfSystemMismatch() public {
        address badRegistry = makeAddr("BAD_REGISTRY");

        mockSystemComponent(_poolOracle, badRegistry);
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_rootPriceOracle), _poolOracle));
        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));
    }

    function test_RevertsIfRegisteringExistingPool() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRegistered.selector, _token));
        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));
    }

    function test_EmitsPoolRegisteredEvent() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        vm.expectEmit(true, true, true, true);
        emit PoolRegistered(_token, address(_poolOracle));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));
    }

    function test_RegisterPoolMapping() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));

        assertEq(address(_rootPriceOracle.poolMappings(_token)), _poolOracle);
    }
}

contract ReplacePoolMapping is RootPriceOracleTests {
    function test_RevertsIfPoolAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        _rootPriceOracle.replacePoolMapping(address(0), ISpotPriceOracle(_poolOracle), ISpotPriceOracle(_tokenOracle));
    }

    function test_RevertsIfOldOracleAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "oldOracle"));
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(address(0)), ISpotPriceOracle(_poolOracle));
    }

    function test_RevertsIfNewOracleAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newOracle"));
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_poolOracle), ISpotPriceOracle(address(0)));
    }

    function test_RevertsIfSystemMismatch() public {
        address badRegistry = makeAddr("BAD_REGISTRY");
        mockSystemComponent(_poolOracle, badRegistry);
        vm.expectRevert(abi.encodeWithSelector(Errors.SystemMismatch.selector, address(_rootPriceOracle), _poolOracle));
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_tokenOracle), ISpotPriceOracle(_poolOracle));
    }

    function test_RevertsIfOldOracleMismatch() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));
        vm.expectRevert(
            abi.encodeWithSelector(RootPriceOracle.ReplaceOldMismatch.selector, _token, _tokenOracle, address(0))
        );
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_tokenOracle), ISpotPriceOracle(_poolOracle));
    }

    function test_RevertsIfNewOracleMatchesOldOracle() public {
        mockSystemComponent(_tokenOracle, address(_systemRegistry));
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_tokenOracle));
        assertEq(address(_rootPriceOracle.poolMappings(_token)), _tokenOracle);

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.ReplaceAlreadyMatches.selector, _token, _tokenOracle));
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_tokenOracle), ISpotPriceOracle(_tokenOracle));
    }

    function test_ReplacePoolMapping() public {
        mockSystemComponent(_tokenOracle, address(_systemRegistry));
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_tokenOracle));
        assertEq(address(_rootPriceOracle.poolMappings(_token)), _tokenOracle);

        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_tokenOracle), ISpotPriceOracle(_poolOracle));
        assertEq(address(_rootPriceOracle.poolMappings(_token)), address(_poolOracle));
    }

    function test_EmitsPoolRegistrationReplacedEvent() public {
        mockSystemComponent(_tokenOracle, address(_systemRegistry));
        mockSystemComponent(_poolOracle, address(_systemRegistry));

        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_tokenOracle));
        assertEq(address(_rootPriceOracle.poolMappings(_token)), _tokenOracle);

        vm.expectEmit(true, true, true, true);
        emit PoolRegistrationReplaced(_token, _tokenOracle, _poolOracle);
        _rootPriceOracle.replacePoolMapping(_token, ISpotPriceOracle(_tokenOracle), ISpotPriceOracle(_poolOracle));
    }
}

contract RemovePoolMapping is RootPriceOracleTests {
    function test_RevertsIfPoolAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        _rootPriceOracle.removePoolMapping(address(0));
    }

    function test_RevertsIfMappingDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MappingDoesNotExist.selector, _token));
        _rootPriceOracle.removePoolMapping(_token);
    }

    function test_RemovePoolMapping() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));
        _rootPriceOracle.removePoolMapping(_token);
        assertEq(address(_rootPriceOracle.poolMappings(_token)), address(0));
    }

    function test_EmitsPoolRemovedEvent() public {
        mockSystemComponent(_poolOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(_token, ISpotPriceOracle(_poolOracle));
        vm.expectEmit(true, true, true, true);
        emit PoolRemoved(_token);
        _rootPriceOracle.removePoolMapping(_token);
    }
}

contract GetSpotPriceInEth is RootPriceOracleTests {
    function test_RevertsIfTokenAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _rootPriceOracle.getSpotPriceInEth(address(0), _pool);
    }

    function test_RevertsIfPoolAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        _rootPriceOracle.getSpotPriceInEth(_token, address(0));
    }

    function test_RevertsIfMissingTokenOracleForPool() public {
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingSpotPriceOracle.selector, _pool));
        _rootPriceOracle.getSpotPriceInEth(_token, _pool);
    }

    function test_ReturnsRawPriceIfActualTokenIsWETH() public {
        uint256 rawPrice = 500;

        mockSystemComponent(_poolOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(_pool, ISpotPriceOracle(_poolOracle));

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSpotPrice.selector, _token, _pool, WETH_MAINNET),
            abi.encode(rawPrice, WETH_MAINNET)
        );

        assertEq(_rootPriceOracle.getSpotPriceInEth(_token, _pool), rawPrice);
    }

    function test_RevertsIfMissingTokenOracleForActualToken() public {
        address pool = makeAddr("POOL_ADDRESS");
        uint256 rawPrice = 500;

        mockSystemComponent(_poolOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(pool, ISpotPriceOracle(_poolOracle));

        address __actualToken = address(new MockERC20());

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSpotPrice.selector, _token, pool, WETH_MAINNET),
            abi.encode(rawPrice, __actualToken)
        );

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingTokenOracle.selector, __actualToken));
        _rootPriceOracle.getSpotPriceInEth(_token, pool);
    }

    function test_ReturnsConvertedPriceIfActualTokenIsNotWETH() public {
        uint256 rawPrice = 358_428;
        uint256 actualTokenPriceInEth = 545_450_000_000_000;

        mockSystemComponent(_poolOracle, address(_systemRegistry));
        mockSystemComponent(_tokenOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(_pool, ISpotPriceOracle(_poolOracle));
        _rootPriceOracle.registerMapping(_actualToken, IPriceOracle(_tokenOracle));

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSpotPrice.selector, _token, _pool, WETH_MAINNET),
            abi.encode(rawPrice, _actualToken)
        );

        vm.mockCall(
            _tokenOracle,
            abi.encodeWithSelector(IPriceOracle.getPriceInEth.selector, _actualToken),
            abi.encode(actualTokenPriceInEth)
        );

        vm.mockCall(WETH_MAINNET, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(
            _actualToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals)
        );

        uint256 expectedPrice = rawPrice * actualTokenPriceInEth / (10 ** actualTokenDecimals);

        assertEq(_rootPriceOracle.getSpotPriceInEth(_token, _pool), expectedPrice);
    }
}

contract SafePricingThresholds is RootPriceOracleTests {
    function test_RevertsIfTokenAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _rootPriceOracle.setSafeSpotPriceThreshold(address(0), 100);
    }

    function test_RevertsIfThresholdIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "threshold"));
        _rootPriceOracle.setSafeSpotPriceThreshold(WETH_MAINNET, 0);
    }

    function test_RevertsIfThresholdExceedsPrecision() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "threshold"));
        _rootPriceOracle.setSafeSpotPriceThreshold(WETH_MAINNET, 100_000);
    }

    function test_setSafePricingThreshold() public {
        vm.expectEmit(true, true, true, true);
        emit SafeSpotPriceThresholdUpdated(WETH_MAINNET, 100);
        _rootPriceOracle.setSafeSpotPriceThreshold(WETH_MAINNET, 100);
        assertEq(_rootPriceOracle.safeSpotPriceThresholds(WETH_MAINNET), 100);
    }
}

contract GetRangePricesLP is RootPriceOracleTests {
    address private _token1;
    address private _token2;

    function setUp() public override {
        super.setUp();

        _token1 = makeAddr("TOKEN1");
        _token2 = makeAddr("TOKEN2");

        vm.label(_token1, "_token1");
        vm.label(_token2, "_token2");

        mockSystemComponent(_poolOracle, address(_systemRegistry));
        mockSystemComponent(_tokenOracle, address(_systemRegistry));
        _rootPriceOracle.registerPoolMapping(_pool, ISpotPriceOracle(_poolOracle));

        _rootPriceOracle.registerMapping(_actualToken, IPriceOracle(_tokenOracle));
        _rootPriceOracle.registerMapping(_token1, IPriceOracle(_tokenOracle));
        _rootPriceOracle.registerMapping(_token2, IPriceOracle(_tokenOracle));

        vm.mockCall(
            _actualToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals)
        );
        vm.mockCall(_token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals));
        vm.mockCall(_token1, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals));
        vm.mockCall(_token2, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals));
    }

    function test_RevertIfNoThreshold() public {
        _setupBasicSafePricingScenario();

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.NoThresholdFound.selector, _token1));
        _rootPriceOracle.getRangePricesLP(_token, _pool, _actualToken);
    }

    function test_getRangePricesLP_RevertsWhenEmptyReserves() public {
        _rootPriceOracle.setSafeSpotPriceThreshold(_token1, 1000);
        _rootPriceOracle.setSafeSpotPriceThreshold(_token2, 1000);

        // Mock empty reserves
        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](0);

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSafeSpotPriceInfo.selector, _pool, _token, _actualToken),
            abi.encode(35_000_000 * 1e18, reserves)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "reserves"));
        (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) =
            _rootPriceOracle.getRangePricesLP(_token, _pool, _actualToken);
    }

    function test_getRangePricesLP_ReturnsZeroWhenZeroTotalSupply() public {
        _rootPriceOracle.setSafeSpotPriceThreshold(_token1, 1000);
        _rootPriceOracle.setSafeSpotPriceThreshold(_token2, 1000);

        // Mock reserves with zero total supply
        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](2);

        reserves[0] = ISpotPriceOracle.ReserveItemInfo({
            token: _token1,
            reserveAmount: 21.5e24,
            rawSpotPrice: 0.9e6,
            actualQuoteToken: _actualToken
        });
        reserves[1] = ISpotPriceOracle.ReserveItemInfo({
            token: _token2,
            reserveAmount: 13.7e24,
            rawSpotPrice: 1.005e6,
            actualQuoteToken: _actualToken
        });

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSafeSpotPriceInfo.selector, _pool, _token, _actualToken),
            abi.encode(0, reserves) // zero total supply
        );

        (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) =
            _rootPriceOracle.getRangePricesLP(_token, _pool, _actualToken);

        assertEq(safePriceInQuote, 0);
        assertEq(spotPriceInQuote, 0);
        assertEq(isSpotSafe, false);
    }

    // @dev Pass safe threshold test by setting it to 10% (token 1 is 9% diff)
    function test_getRangePricesLP_PassThreshold() public {
        _setupBasicSafePricingScenario();

        // set threshold to 10% (first token is 9, second is 0, so should pass)
        _rootPriceOracle.setSafeSpotPriceThreshold(_token1, 1000);
        _rootPriceOracle.setSafeSpotPriceThreshold(_token2, 1000);

        (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) =
            _rootPriceOracle.getRangePricesLP(_token, _pool, _actualToken);

        assertEq(safePriceInQuote, 1_003_872);
        assertEq(spotPriceInQuote, 946_242);
        assertEq(isSpotSafe, true);
    }

    // @dev Fail safe threshold test by setting it to 5% (token 1 is 9% diff)
    function test_getRangePricesLP_FailThreshold() public {
        _setupBasicSafePricingScenario();

        // set threshold to 5% (first token is 9, second is 0, so should pass)
        _rootPriceOracle.setSafeSpotPriceThreshold(_token1, 500);
        _rootPriceOracle.setSafeSpotPriceThreshold(_token2, 500);

        (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) =
            _rootPriceOracle.getRangePricesLP(_token, _pool, _actualToken);

        assertEq(safePriceInQuote, 1_003_872);
        assertEq(spotPriceInQuote, 946_242);
        assertEq(isSpotSafe, false);
    }

    function _setupBasicSafePricingScenario() internal {
        //
        // mock reserves
        ISpotPriceOracle.ReserveItemInfo[] memory reserves = new ISpotPriceOracle.ReserveItemInfo[](2);

        reserves[0] = ISpotPriceOracle.ReserveItemInfo({
            token: _token1,
            reserveAmount: 21.5e24,
            rawSpotPrice: 0.9e6,
            actualQuoteToken: _actualToken
        });
        reserves[1] = ISpotPriceOracle.ReserveItemInfo({
            token: _token2,
            reserveAmount: 13.7e24,
            rawSpotPrice: 1.005e6,
            actualQuoteToken: _actualToken
        });

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSafeSpotPriceInfo.selector, _pool, _token, _actualToken),
            abi.encode(35_000_000 * 1e18, reserves)
        );

        // token 1
        setRootPrice(_token1, 0.998 * 1e18);
        setSpotPrice(_token1, reserves[0].rawSpotPrice);
        // token 2
        setRootPrice(_token2, 1.001 * 1e18);
        setSpotPrice(_token2, reserves[1].rawSpotPrice);

        // actual token
        setRootPrice(_actualToken, 1.001 * 1e18);
        setSpotPrice(_actualToken, 1.001 * 1e18);
    }

    function setRootPrice(address token, uint256 price) internal {
        // NOTE: hack to avoid strange line length issue
        bytes memory selector = abi.encodeWithSelector(IPriceOracle.getPriceInEth.selector, token);
        vm.mockCall(_tokenOracle, selector, abi.encode(price));
    }

    function setSpotPrice(address token, uint256 price) private {
        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSpotPrice.selector, token, _pool, _actualToken),
            abi.encode(price, _actualToken)
        );
    }
}

contract GetPriceInQuote is RootPriceOracleTests {
    address private _token1;
    address private _token1Oracle;
    uint8 private _token1Decimals = 24;

    address private _token2;
    address private _token2Oracle;
    uint8 private _token2Decimals = 6;

    function setUp() public override {
        super.setUp();

        _token1 = makeAddr("NEAR");
        _token1Oracle = makeAddr("NEAROracle");
        vm.mockCall(_token1, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_token1Decimals));
        mockSystemComponent(_token1Oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(_token1, IPriceOracle(_token1Oracle));

        _token2 = makeAddr("USDC");
        _token2Oracle = makeAddr("USDCOracle");
        vm.mockCall(_token2, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_token2Decimals));
        mockSystemComponent(_token2Oracle, address(_systemRegistry));
        _rootPriceOracle.registerMapping(_token2, IPriceOracle(_token2Oracle));
    }

    function test_HighDecimalQuote() public {
        // Current NEAR Price: $2.80  - 0.00116049e18 ETH
        // Current USDC Price: $1.00  - 0.00042001e18 ETH

        _setGetPriceInEth(_token1, _token1Oracle, 0.00116049e18);
        _setGetPriceInEth(_token2, _token2Oracle, 0.00042001e18);

        // solhint-disable-next-line no-unused-vars
        uint256 calculatedPrice = uint256(0.3571e24);
        uint256 safePrice = _rootPriceOracle.getPriceInQuote(_token2, _token1);

        // Roughly $1/$2.8 or 0.00042001 / 0.00116049
        assertEq(safePrice, 0.36192470421976923540918e24);
    }

    function _setGetPriceInEth(address token, address oracle, uint256 price) internal {
        bytes memory selector = abi.encodeWithSelector(IPriceOracle.getPriceInEth.selector, token);
        vm.mockCall(oracle, selector, abi.encode(price));
    }
}
