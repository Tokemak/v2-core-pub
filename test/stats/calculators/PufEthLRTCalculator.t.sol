// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { PufEthLRTCalculator } from "src/stats/calculators/PufEthLRTCalculator.sol";

import { TOKE_MAINNET, WETH_MAINNET, PUFFER_VAULT_MAINNET } from "test/utils/Addresses.sol";

contract PufEthLRTCalculatorTests is Test {
    AccessController private _accessController;
    PufEthLRTCalculator private _calculator;

    event PufEthVaultSet(address pufferVault);

    function setUp() public {
        _setUp(20_112_386);
    }

    function test_calculateEthPerToken() public {
        // Actual value from the contract is 1_013_185_872_370_260_061
        assertApproxEqAbs(_calculator.calculateEthPerToken(), 1_013_185_872_370_260_061, 1e17, "ethPerToken");
    }

    function test_usePriceAsDiscount_IsFalse() public {
        assertEq(_calculator.usePriceAsDiscount(), false, "usePriceAsDiscount");
    }

    function test_setPufEthVault_RevertIf_NotCalledByRole() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _calculator.setPufEthVault(address(1));

        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        _calculator.setPufEthVault(address(1));
    }

    function test_setPufEthVault_RevertIf_ZeroAddress() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_pufferVault"));
        _calculator.setPufEthVault(address(0));
    }

    function test_setPufEthVault_UpdatesValue() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));
        _calculator.setPufEthVault(address(1));

        assertEq(address(_calculator.pufferVault()), address(1));
    }

    function test_setPufEthVault_EmitsEvent() public {
        _accessController.grantRole(Roles.STATS_GENERAL_MANAGER, address(this));

        vm.expectEmit(true, true, true, true);
        emit PufEthVaultSet(address(1));
        _calculator.setPufEthVault(address(1));
    }

    function _setUp(uint256 targetBlock) private {
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, PUFFER_VAULT_MAINNET),
            abi.encode(1e18)
        );

        _calculator = PufEthLRTCalculator(Clones.clone(address(new PufEthLRTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);

        LSTCalculatorBase.InitData memory initData =
            LSTCalculatorBase.InitData({ lstTokenAddress: PUFFER_VAULT_MAINNET });
        PufEthLRTCalculator.PufEthInitData memory pufEthInitData = PufEthLRTCalculator.PufEthInitData({
            pufferVault: PUFFER_VAULT_MAINNET,
            baseInitData: abi.encode(initData)
        });
        _calculator.initialize(dependantAprs, abi.encode(pufEthInitData));
    }
}
