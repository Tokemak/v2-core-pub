// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { WSTETH_MAINNET } from "test/utils/Addresses.sol";
import { Test } from "forge-std/Test.sol";
import { IwstEth } from "src/interfaces/external/lido/IwstEth.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/utils/Errors.sol";

contract WstETHEthOracleTests is Test {
    uint256 private _addrIx;

    IRootPriceOracle private _rootPriceOracle;
    ISystemRegistry private _systemRegistry;
    WstETHEthOracle private _oracle;
    IwstEth private _wstETH;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_229);
        vm.selectFork(mainnetFork);

        _rootPriceOracle = IRootPriceOracle(vm.addr(324));
        _systemRegistry = _generateSystemRegistry(address(_rootPriceOracle));
        _oracle = new WstETHEthOracle(_systemRegistry, WSTETH_MAINNET);
        _wstETH = IwstEth(WSTETH_MAINNET);
    }

    function testBasicPrice() public {
        _mockRootPrice(_wstETH.stETH(), 999_259_060_000_000_000);
        uint256 price = _oracle.getPriceInEth(address(_wstETH));

        assertApproxEqAbs(price, 1_125_000_000_000_000_000, 1e17);
    }

    function testOnlyWeth() public {
        address fakeAddr = vm.addr(34_343);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, fakeAddr));
        _oracle.getPriceInEth(address(fakeAddr));
    }

    function _generateToken(uint8 decimals) internal returns (address) {
        address addr = vm.addr(239_874 + _addrIx++);
        vm.mockCall(addr, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
        return addr;
    }

    function _mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function _generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}
