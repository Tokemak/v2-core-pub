// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { IweETH } from "src/interfaces/external/etherfi/IweETH.sol";
import { IeETH } from "src/interfaces/external/etherfi/IeETH.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { EethOracle } from "src/oracles/providers/EethOracle.sol";
import { Errors } from "src/utils/Errors.sol";

contract EethOracleTests is Test {
    address private weETH;
    address private eETH;
    IRootPriceOracle private _rootPriceOracle;
    ISystemRegistry private _systemRegistry;
    EethOracle private _oracle;

    function setUp() public {
        weETH = makeAddr("weETH");
        eETH = makeAddr("eETH");

        _rootPriceOracle = IRootPriceOracle(makeAddr("rootOracle"));
        _systemRegistry = _generateSystemRegistry(address(_rootPriceOracle));

        vm.mockCall(weETH, abi.encodeWithSelector(IweETH.eETH.selector), abi.encode(eETH));
        vm.mockCall(eETH, abi.encodeWithSelector(IeETH.decimals.selector), abi.encode(18));

        _oracle = new EethOracle(_systemRegistry, weETH);
    }

    function test_constructor_RevertIf_NotContract() public {
        vm.expectRevert();
        new EethOracle(_systemRegistry, address(1));
    }

    function test_constructor_RevertIf_WeethEmpty() public {
        vm.mockCall(weETH, abi.encodeWithSelector(IweETH.eETH.selector), abi.encode(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_weETH"));
        new EethOracle(_systemRegistry, address(0));
    }

    function test_constructor_RevertIf_EethEmpty() public {
        vm.mockCall(weETH, abi.encodeWithSelector(IweETH.eETH.selector), abi.encode(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "eETH"));
        new EethOracle(_systemRegistry, weETH);
    }

    function test_constructor_RevertIf_EethNot18Decimals() public {
        vm.mockCall(eETH, abi.encodeWithSelector(IeETH.decimals.selector), abi.encode(17));

        vm.expectRevert(abi.encodeWithSelector(EethOracle.InvalidDecimals.selector, eETH, 17));
        new EethOracle(_systemRegistry, weETH);
    }

    function test_getPriceInEth_RevertIf_NotEethToken() public {
        address token = makeAddr("badToken");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, token));
        _oracle.getPriceInEth(token);
    }

    function test_getPriceInEth_PerformsConversion() public {
        _mockRootPrice(address(weETH), 1e18);
        _mockEETHByWeETH(2e18);

        uint256 eethPrice = _oracle.getPriceInEth(eETH);

        assertEq(eethPrice, 0.5e18, "price");
    }

    function _mockEETHByWeETH(uint256 per) internal {
        vm.mockCall(address(weETH), abi.encodeWithSelector(IweETH.getEETHByWeETH.selector, 1 ether), abi.encode(per));
    }

    function _mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function _generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = makeAddr("registry");
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}
