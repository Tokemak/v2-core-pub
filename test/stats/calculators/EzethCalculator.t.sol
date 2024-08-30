// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { EzethLRTCalculator } from "src/stats/calculators/EzethLRTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { EZETH_MAINNET, TOKE_MAINNET, WETH_MAINNET, RENZO_RESTAKE_MANAGER_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Errors } from "src/utils/Errors.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

contract EzethLRTCalculatorTests is Test {
    AccessController private _accessController;
    EzethLRTCalculator private _calculator;

    event RenzoRestakeManagerSet(address newOracle);

    function setUp() public {
        _setUp(19_984_041);
    }

    // totalTVL - 1065401720260635856693585
    // totalSupply - 1054068892374051626531219
    function test_calculateEthPerToken() public {
        assertApproxEqAbs(_calculator.calculateEthPerToken(), 1_010_751_505_872_694_525, 1e17, "ethPerToken");
    }

    function test_Returns1e18_WhenTotalSupply_Zero() public {
        vm.mockCall(EZETH_MAINNET, abi.encodeWithSignature("totalSupply()"), abi.encode(0));

        uint256 ret = _calculator.calculateEthPerToken();
        assertEq(ret, 1e18);
    }

    function test_ReturnsZero_WhenTotalTVL_Zero() public {
        uint256[][] memory retArr1 = new uint256[][](0);
        uint256[] memory retArr2 = new uint256[](0);

        vm.mockCall(
            RENZO_RESTAKE_MANAGER_MAINNET, abi.encodeWithSignature("calculateTVLs()"), abi.encode(retArr1, retArr2, 0)
        );

        uint256 ret = _calculator.calculateEthPerToken();
        assertEq(ret, 0);
    }

    function test_Returns1e18_WhenBoth_Zero() public {
        vm.mockCall(EZETH_MAINNET, abi.encodeWithSignature("totalSupply()"), abi.encode(0));

        uint256[][] memory retArr1 = new uint256[][](0);
        uint256[] memory retArr2 = new uint256[](0);

        vm.mockCall(
            RENZO_RESTAKE_MANAGER_MAINNET, abi.encodeWithSignature("calculateTVLs()"), abi.encode(retArr1, retArr2, 0)
        );

        uint256 ret = _calculator.calculateEthPerToken();
        assertEq(ret, 1e18);
    }

    function test_usePriceAsDiscount_IsFalse() public {
        assertEq(_calculator.usePriceAsDiscount(), false, "usePriceAsDiscount");
    }

    function test_setRenzoRestakeManager_RevertIf_NotCalledByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _calculator.setRenzoRestakeManager(address(1));

        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        _calculator.setRenzoRestakeManager(address(1));
    }

    function test_setRenzoRestakeManager_RevertIf_ZeroAddress() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newRestakeManager"));
        _calculator.setRenzoRestakeManager(address(0));
    }

    function test_setRenzoRestakeManager_UpdatesValue() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));
        _calculator.setRenzoRestakeManager(address(1));

        assertEq(address(_calculator.renzoRestakeManger()), address(1), "newAddress");
    }

    function test_setRenzoRestakeManager_EmitsEvent() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit RenzoRestakeManagerSet(address(1));
        _calculator.setRenzoRestakeManager(address(1));
    }

    function _setUp(uint256 targetBlock) private returns (EzethLRTCalculator) {
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, EZETH_MAINNET),
            abi.encode(1e18)
        );

        _calculator = EzethLRTCalculator(Clones.clone(address(new EzethLRTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);

        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: EZETH_MAINNET });
        EzethLRTCalculator.EzEthInitData memory ezEthInitData = EzethLRTCalculator.EzEthInitData({
            restakeManager: RENZO_RESTAKE_MANAGER_MAINNET,
            baseInitData: abi.encode(initData)
        });
        _calculator.initialize(dependantAprs, abi.encode(ezEthInitData));

        return _calculator;
    }
}
