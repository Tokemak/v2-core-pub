// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { CbethLSTCalculator } from "src/stats/calculators/CbethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { CBETH_MAINNET, TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract CbethLSTCalculatorTest is Test {
    function testStethEthPerToken() public {
        checkEthPerToken(17_272_708, 1_037_000_314_216_931_031);
        checkEthPerToken(17_279_454, 1_037_145_502_666_710_522);
        checkEthPerToken(17_286_461, 1_037_260_648_657_762_304);
        checkEthPerToken(17_293_521, 1_037_389_203_733_762_949);
        checkEthPerToken(17_393_019, 1_039_032_065_195_261_641);
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, CBETH_MAINNET),
            abi.encode(1e18)
        );

        CbethLSTCalculator calculator = new CbethLSTCalculator(systemRegistry);
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: CBETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(calculator.calculateEthPerToken(), expected);
    }
}
