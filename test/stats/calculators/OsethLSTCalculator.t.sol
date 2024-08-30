// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { OsethLSTCalculator } from "src/stats/calculators/OsethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { OSETH_MAINNET, TOKE_MAINNET, WETH_MAINNET, STAKEWISE_OSETH_PRICE_ORACLE } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Errors } from "src/utils/Errors.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

contract OsethLSTCalculatorTests is Test {
    AccessController private _accessController;
    OsethLSTCalculator private _calculator;

    event OsEthPriceOracleSet(address newOracle);

    function setUp() public {
        _setUp(19_590_178);
    }

    function test_calculateEthPerToken() public {
        assertEq(_calculator.calculateEthPerToken(), 1_012_783_667_542_821_111, "ethPerToken");
    }

    function test_usePriceAsBacking_IsFalse() public {
        assertEq(_calculator.usePriceAsBacking(), false, "usePriceAsBacking");
    }

    function test_setOsEthPriceOracle_RevertIf_NotCalledByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _calculator.setOsEthPriceOracle(address(1));

        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        _calculator.setOsEthPriceOracle(address(1));
    }

    function test_setOsEthPriceOracle_RevertIf_ZeroAddress() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "priceOracle"));
        _calculator.setOsEthPriceOracle(address(0));
    }

    function test_setOsEthPriceOracle_UpdatesValue() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));
        _calculator.setOsEthPriceOracle(address(1));

        assertEq(address(_calculator.osEthPriceOracle()), address(1), "newAddress");
    }

    function test_setOsEthPriceOracle_EmitsEvent() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit OsEthPriceOracleSet(address(1));
        _calculator.setOsEthPriceOracle(address(1));
    }

    function _setUp(uint256 targetBlock) private returns (OsethLSTCalculator) {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), targetBlock);
        vm.selectFork(mainnetFork);

        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(_accessController));
        _accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));

        // required for initialization, but not part of test surface area
        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, OSETH_MAINNET),
            abi.encode(1e18)
        );

        _calculator = OsethLSTCalculator(Clones.clone(address(new OsethLSTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);

        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: OSETH_MAINNET });
        OsethLSTCalculator.OsEthInitData memory osEthInitData = OsethLSTCalculator.OsEthInitData({
            priceOracle: STAKEWISE_OSETH_PRICE_ORACLE,
            baseInitData: abi.encode(initData)
        });
        _calculator.initialize(dependantAprs, abi.encode(osEthInitData));

        return _calculator;
    }
}
