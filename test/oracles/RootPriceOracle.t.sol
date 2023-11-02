// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { IwstEth } from "src/interfaces/external/lido/IwstEth.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";

contract RootPriceOracleTests is Test {
    SystemRegistry internal _systemRegistry;
    AccessController private _accessController;
    RootPriceOracle internal _rootPriceOracle;

    address internal _pool;
    address internal _token;
    address internal _poolOracle;
    address internal _tokenOracle;
    address internal _actualToken;

    event PoolRegistered(address indexed pool, address indexed oracle);
    event PoolRegistrationReplaced(address indexed pool, address indexed oldOracle, address indexed newOracle);
    event PoolRemoved(address indexed pool);

    error AlreadyRegistered(address token);
    error MissingTokenOracle(address token);
    error MappingDoesNotExist(address token);
    error ReplaceOldMismatch(address token, address oldExpected, address oldActual);
    error ReplaceAlreadyMatches(address token, address newOracle);

    function setUp() public {
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));
        _rootPriceOracle = new RootPriceOracle(_systemRegistry);

        _pool = makeAddr("POOL");
        _token = makeAddr("TOKEN");
        _poolOracle = makeAddr("POOL_ORACLE");
        _tokenOracle = makeAddr("TOKEN_ORACLE");
        _actualToken = makeAddr("ACTUAL_TOKEN");

        vm.label(_pool, "_pool");
        vm.label(_token, "_token");
        vm.label(_poolOracle, "_poolOracle");
        vm.label(_tokenOracle, "_tokenOracle");
        vm.label(_actualToken, "_actualToken");
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
        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingTokenOracle.selector, _pool));
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

        vm.mockCall(
            _poolOracle,
            abi.encodeWithSelector(ISpotPriceOracle.getSpotPrice.selector, _token, pool, WETH_MAINNET),
            abi.encode(rawPrice, _actualToken)
        );

        vm.expectRevert(abi.encodeWithSelector(RootPriceOracle.MissingTokenOracle.selector, _actualToken));
        _rootPriceOracle.getSpotPriceInEth(_token, pool);
    }

    function test_ReturnsConvertedPriceIfActualTokenIsNotWETH() public {
        uint256 rawPrice = 358_428;
        uint256 actualTokenPriceInEth = 545_450_000_000_000;
        uint256 actualTokenDecimals = 6;

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

        vm.mockCall(
            _actualToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(actualTokenDecimals)
        );

        uint256 expectedPrice = rawPrice * actualTokenPriceInEth / (10 ** actualTokenDecimals);

        assertEq(_rootPriceOracle.getSpotPriceInEth(_token, _pool), expectedPrice);
    }
}
