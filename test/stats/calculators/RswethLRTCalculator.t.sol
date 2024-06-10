// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { RswethLRTCalculator } from "src/stats/calculators/RswethLRTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { TOKE_MAINNET, WETH_MAINNET, RSWETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

contract RswethLSTCalculatorTest is Test {
    function testRstethEthPerToken() public {
        checkEthPerToken(19_900_019, 1_007_819_009_487_715_209);
        checkEthPerToken(19_950_283, 1_008_359_973_494_992_706);
        checkEthPerToken(20_000_000, 1_009_118_717_562_649_966);
        checkEthPerToken(20_040_454, 1_009_551_897_400_438_382);
        checkEthPerToken(20_062_850, 1_009_863_394_871_064_680);
    }

    function checkEthPerToken(uint256 targetBlock, uint256 expected) private {
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, RSWETH_MAINNET),
            abi.encode(1e18)
        );

        RswethLRTCalculator calculator =
            RswethLRTCalculator(Clones.clone(address(new RswethLRTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: RSWETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(calculator.calculateEthPerToken(), expected);
    }
}
