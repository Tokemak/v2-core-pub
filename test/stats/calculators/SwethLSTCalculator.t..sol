// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { SwethLSTCalculator } from "src/stats/calculators/SwethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { SWETH_MAINNET, TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract SwethLSTCalculatorTest is Test {
    function testStethEthPerToken() public {
        checkEthPerToken(17_272_708, 1_026_937_210_012_217_451);
        checkEthPerToken(17_279_454, 1_026_937_210_012_217_451);
        checkEthPerToken(17_286_461, 1_026_937_210_012_217_451);
        checkEthPerToken(17_293_521, 1_027_139_938_284_152_259);
        checkEthPerToken(17_393_019, 1_028_031_999_300_723_065);
    }

    function checkEthPerToken(uint256 targetBlock, uint256 expected) private {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), targetBlock);
        vm.selectFork(mainnetFork);

        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));

        // required for initialization, but not part of test surface area
        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, SWETH_MAINNET),
            abi.encode(1e18)
        );

        SwethLSTCalculator calculator = new SwethLSTCalculator(systemRegistry);
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: SWETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(calculator.calculateEthPerToken(), expected);
    }
}
