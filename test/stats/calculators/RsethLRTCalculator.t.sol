// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { RsethLRTCalculator } from "src/stats/calculators/RsethLRTCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { TOKE_MAINNET, WETH_MAINNET, RSETH_MAINNET } from "test/utils/Addresses.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

contract RsethLRTCalculatorTests is Test {
    function test_calculateEthPerToken_CorrectStandardCalculation() public {
        RsethLRTCalculator calculator = _setUp(20_019_782);

        assertEq(calculator.calculateEthPerToken(), 1_013_844_309_207_288_936, "ethPerToken");
    }

    function test_UsePriceAsBacking_False() public {
        RsethLRTCalculator calculator = _setUp(20_019_782);

        assertEq(calculator.usePriceAsBacking(), false, "usePriceAsBacking");
    }

    function _setUp(uint256 targetBlock) private returns (RsethLRTCalculator) {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), targetBlock);
        vm.selectFork(mainnetFork);

        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));

        // required for initialization, but not part of test surface area
        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, RSETH_MAINNET),
            abi.encode(0.99609344e18)
        );

        RsethLRTCalculator calculator =
            RsethLRTCalculator(Clones.clone(address(new RsethLRTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: RSETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        return calculator;
    }
}
