// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { StethLSTCalculator } from "src/stats/calculators/StethLSTCalculator.sol";
import { RethLSTCalculator } from "src/stats/calculators/RethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { RETH_MAINNET, TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract RethLSTCalculatorTest is Test {
    function testStethEthPerToken() public {
        checkEthPerToken(17_272_708, 1_070_685_171_168_549_185);
        checkEthPerToken(17_279_454, 1_070_789_567_827_940_207);
        checkEthPerToken(17_286_461, 1_070_999_366_517_302_681);
        checkEthPerToken(17_293_521, 1_071_137_533_974_942_357);
        checkEthPerToken(17_393_019, 1_072_763_940_592_978_363);
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, RETH_MAINNET),
            abi.encode(1e18)
        );

        RethLSTCalculator calculator = new RethLSTCalculator(systemRegistry);
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: RETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(calculator.calculateEthPerToken(), expected);
    }
}
