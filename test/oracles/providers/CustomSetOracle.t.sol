// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { CustomSetOracle } from "src/oracles/providers/CustomSetOracle.sol";

contract CustomSetOracleTest is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    CustomSetOracle private _oracle;

    uint256 internal maxAge = 1000;

    event TokensRegistered(address[] tokens, uint256[] maxAges);
    event PricesSet(address[] tokens, uint256[] ethPrices, uint256[] queriedTimestamps);
    event MaxAgeSet(uint256 maxAge);
    event TokensUnregistered(address[] tokens);

    function setUp() external {
        _systemRegistry = new SystemRegistry(vm.addr(100), vm.addr(101));

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _oracle = new CustomSetOracle(_systemRegistry, maxAge);

        _accessController.grantRole(Roles.ORACLE_MANAGER_ROLE, address(this));
    }

    function test_construction_MaxAgeIsSet() public {
        assertEq(_oracle.maxAge(), maxAge);
    }

    function test_construction_MaxAgeMustBeLessThanUint32() public {
        uint256 invalidAge = uint256(type(uint32).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidAge.selector, invalidAge));
        new CustomSetOracle(_systemRegistry, invalidAge);
    }

    function test_construction_MaxAgeMustBeGreaterThanZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxAge"));
        new CustomSetOracle(_systemRegistry, 0);
    }

    function test_registerToken_InputsMustBeOfSameLength() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2, "token+ages"));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_TokenInputMustHaveValues() public {
        address[] memory tokens = new address[](0);
        uint256[] memory ages = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_AgesInputMustHaveValues() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 0, "token+ages"));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_RegistersAToken() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 100;

        _oracle.registerTokens(tokens, ages);

        assertTrue(_oracle.isRegistered(address(1)));
    }

    function test_registerToken_EmitsTokensRegisteredEvent() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 100;

        vm.expectEmit(true, true, true, true);
        emit TokensRegistered(tokens, ages);
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_RevertIf_NotCalledByOwner() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        address caller = address(5);

        tokens[0] = address(1);
        ages[0] = 100;

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _oracle.registerTokens(tokens, ages);
        vm.stopPrank();
    }

    function test_registerToken_RegistersMultipleTokens() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 200;

        _oracle.registerTokens(tokens, ages);

        assertTrue(_oracle.isRegistered(address(1)));
        assertTrue(_oracle.isRegistered(address(2)));

        (, uint32 ageOne,) = _oracle.prices(address(1));
        (, uint32 ageTwo,) = _oracle.prices(address(2));
        assertEq(ageOne, 100);
        assertEq(ageTwo, 200);
    }

    function test_registerToken_RevertsIf_TokenAddressIsZero() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(0);
        ages[1] = 200;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_RevertsIf_MaxAgeIsZero() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxAge"));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_RevertsIf_MaxAgeIsGreaterThanSystemAllows() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = maxAge + 1;

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidAge.selector, maxAge + 1));
        _oracle.registerTokens(tokens, ages);
    }

    function test_registerToken_RevertsIf_RegisteredTheSameTokenTwice() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = maxAge - 1;

        _oracle.registerTokens(tokens, ages);

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.AlreadyRegistered.selector, address(1)));
        _oracle.registerTokens(tokens, ages);
    }

    function test_setMaxAge_RevertIf_NotCalledByOwner() public {
        address caller = address(5);

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _oracle.setMaxAge(10_000);
        vm.stopPrank();
    }

    function test_setMaxAge_UpdatesMaxAge() public {
        assertFalse(_oracle.maxAge() == 888);
        _oracle.setMaxAge(888);
        assertEq(_oracle.maxAge(), 888);
    }

    function test_setMaxAge_EmitsMaxAgeSetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit MaxAgeSet(888);
        _oracle.setMaxAge(888);
    }

    function test_setMaxAge_RevertIf_AgeGreaterThanUint32() public {
        uint256 invalidAge = uint256(type(uint32).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidAge.selector, invalidAge));
        _oracle.setMaxAge(invalidAge);
    }

    function test_setMaxAge_RevertIf_AgeZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxAge"));
        _oracle.setMaxAge(0);
    }

    function test_setMaxAge_PreventsNewlyTokensRegisteredFromBeingLess() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setMaxAge(99);

        tokens[0] = address(2);

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidAge.selector, 100));
        _oracle.registerTokens(tokens, ages);
    }

    function test_updateTokenMaxAge_AllowsUpdateOfAge() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 100;

        _oracle.registerTokens(tokens, ages);

        ages[0] = 200;
        ages[1] = 201;

        _oracle.updateTokenMaxAges(tokens, ages);

        (, uint32 ageOne,) = _oracle.prices(address(1));
        (, uint32 ageTwo,) = _oracle.prices(address(2));

        assertEq(ageOne, 200);
        assertEq(ageTwo, 201);
    }

    function test_updateTokenMaxAge_RevertIf_NotCalledByOwner() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);
        address caller = address(5);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 100;

        _oracle.registerTokens(tokens, ages);

        ages[0] = 200;
        ages[1] = 201;

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _oracle.updateTokenMaxAges(tokens, ages);
        vm.stopPrank();
    }

    function test_updateTokenMaxAge_EmitsTokensRegisteredEvent() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 100;

        _oracle.registerTokens(tokens, ages);

        ages[0] = 200;
        ages[1] = 201;

        vm.expectEmit(true, true, true, true);
        emit TokensRegistered(tokens, ages);
        _oracle.updateTokenMaxAges(tokens, ages);
    }

    function test_updateTokenMaxAge_RevertIf_MaxAgeIsGreaterThanSystemAllows() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);

        tokens[0] = address(1);
        ages[0] = 100;

        tokens[1] = address(2);
        ages[1] = 100;

        _oracle.registerTokens(tokens, ages);

        ages[0] = 200;
        ages[1] = maxAge + 1;

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidAge.selector, maxAge + 1));
        _oracle.updateTokenMaxAges(tokens, ages);
    }

    function test_unregisterTokens_RemovesRegisteredTokens() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setPrices(tokens, prices, timestamps);

        assertEq(_oracle.getPriceInEth(address(1)), 1e18);

        _oracle.unregisterTokens(tokens);

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.TokenNotRegistered.selector, address(1)));
        _oracle.getPriceInEth(address(1));
    }

    function test_unregisterTokens_EmitsTokenUnregisteredEvent() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        vm.expectEmit(true, true, true, true);
        emit TokensUnregistered(tokens);
        _oracle.unregisterTokens(tokens);
    }

    function test_unregisterTokens_RevertIf_NoDataIsPassed() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        _oracle.unregisterTokens(new address[](0));
    }

    function test_unregisterTokens_RevertIf_ZeroAddressPassed() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        tokens[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        _oracle.unregisterTokens(tokens);
    }

    function test_unregisterTokens_RevertIf_TokenIsntRegistered() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        tokens[0] = address(2);

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.InvalidToken.selector, address(2)));
        _oracle.unregisterTokens(tokens);
    }

    function test_isRegistered_ReturnsTrueForRegisteredToken() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 100;

        _oracle.registerTokens(tokens, ages);

        assertTrue(_oracle.isRegistered(address(1)));
    }

    function test_isRegistered_ReturnsFalseForNotRegisteredToken() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 100;

        _oracle.registerTokens(tokens, ages);

        assertFalse(_oracle.isRegistered(address(2)));
    }

    function test_setPrices_TokenInputsMustHaveValue() public {
        address[] memory tokens = new address[](0);
        uint256[] memory prices = new uint256[](2);
        uint256[] memory timestamps = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_InputsMustBeOfSameLength() public {
        address[] memory tokens = new address[](2);
        uint256[] memory prices = new uint256[](0);
        uint256[] memory timestamps = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 0, "token+prices"));
        _oracle.setPrices(tokens, prices, timestamps);

        tokens = new address[](2);
        prices = new uint256[](2);
        timestamps = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 0, "token+timestamps"));
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_RevertsIf_PriceIsGreaterThanU192() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        prices[0] = uint256(type(uint192).max) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(CustomSetOracle.InvalidPrice.selector, address(1), uint256(type(uint192).max) + 1)
        );
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_RevertsIf_QueriedTimestampIsInTheFuture() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;

        _oracle.registerTokens(tokens, ages);

        prices[0] = 1e18;
        timestamps[0] = block.timestamp + 100_000;

        vm.expectRevert(
            abi.encodeWithSelector(CustomSetOracle.InvalidTimestamp.selector, address(1), block.timestamp + 100_000)
        );
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_RevertsIf_DataIsStale() public {
        uint256 baseTimestamp = 1_583_280_000;
        vm.warp(baseTimestamp);

        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;

        _oracle.registerTokens(tokens, ages);

        timestamps[0] = block.timestamp - 100;

        // Setting initial price data
        _oracle.setPrices(tokens, prices, timestamps);

        // Going back in time
        vm.warp(baseTimestamp);
        vm.expectRevert(
            abi.encodeWithSelector(CustomSetOracle.StalePriceDataError.selector, timestamps[0], maxAge, baseTimestamp)
        );
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_RevertsIf_TokenIsntRegistered() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.TokenNotRegistered.selector, address(1)));
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_SetsPrice() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setPrices(tokens, prices, timestamps);

        assertEq(_oracle.getPriceInEth(address(1)), 1e18);
    }

    function test_setPrices_RevertsIf_LatestPriceQueriedEarlierThanCurrent() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setPrices(tokens, prices, timestamps);

        timestamps[0] = 10_000_000 - 200;

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomSetOracle.TimestampOlderThanCurrent.selector, address(1), 10_000_000 - 100, 10_000_000 - 200
            )
        );
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_EmitsPriceSetEvent() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        vm.expectEmit(true, true, true, true);
        emit PricesSet(tokens, prices, timestamps);
        _oracle.setPrices(tokens, prices, timestamps);
    }

    function test_setPrices_CanSetForMultipleTokens() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        uint256[] memory timestamps = new uint256[](2);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        tokens[1] = address(2);

        ages[0] = 1000;
        ages[1] = 1000;

        prices[0] = 1e18;
        prices[1] = 2e18;

        timestamps[0] = 10_000_000 - 100;
        timestamps[1] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setPrices(tokens, prices, timestamps);

        assertTrue(_oracle.isRegistered(address(1)));
        assertTrue(_oracle.isRegistered(address(2)));

        assertEq(_oracle.getPriceInEth(address(1)), 1e18);
        assertEq(_oracle.getPriceInEth(address(2)), 2e18);
    }

    function test_getPriceInEth_RevertsIf_TokenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(CustomSetOracle.TokenNotRegistered.selector, address(8)));
        _oracle.getPriceInEth(address(8));
    }

    function test_getPriceInEth_RevertsIf_PriceIsStale() public {
        address[] memory tokens = new address[](1);
        uint256[] memory ages = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        ages[0] = 1000;
        prices[0] = 1e18;
        timestamps[0] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);
        _oracle.setPrices(tokens, prices, timestamps);

        assertEq(_oracle.getPriceInEth(address(1)), 1e18);

        vm.warp(10_000_000 - 100 + 1000 + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomSetOracle.InvalidAge.selector, (10_000_000 - 100 + 1000 + 1) - (10_000_000 - 100)
            )
        );
        _oracle.getPriceInEth(address(1));
    }

    function test_getPriceInEth_GetsPrice() public {
        address[] memory tokens = new address[](2);
        uint256[] memory ages = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        uint256[] memory timestamps = new uint256[](2);

        vm.warp(10_000_000);

        tokens[0] = address(1);
        tokens[1] = address(2);

        ages[0] = 1000;
        ages[1] = 1000;

        prices[0] = 1e18;
        prices[1] = 2e18;

        timestamps[0] = 10_000_000 - 100;
        timestamps[1] = 10_000_000 - 100;

        _oracle.registerTokens(tokens, ages);

        _oracle.setPrices(tokens, prices, timestamps);

        assertEq(_oracle.getPriceInEth(address(1)), 1e18);
        assertEq(_oracle.getPriceInEth(address(2)), 2e18);
    }
}
