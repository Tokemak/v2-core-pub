// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test, console2 as console } from "forge-std/Test.sol";
import { StethLSTCalculator } from "src/stats/calculators/StethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { STETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";

contract StethLSTCalculatorTest is Test {
    function testStethEthPerToken() public {
        checkEthPerToken(17_272_708, 1_124_349_506_893_718_109);
        checkEthPerToken(17_279_454, 1_124_504_367_992_424_664);
        checkEthPerToken(17_286_461, 1_124_666_417_311_180_217);
        checkEthPerToken(17_293_521, 1_124_835_614_410_438_130);
        checkEthPerToken(17_393_019, 1_126_897_087_511_522_171);
    }

    function checkEthPerToken(uint256 targetBlock, uint256 expected) private {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), targetBlock);
        vm.selectFork(mainnetFork);

        SystemRegistry systemRegistry = new SystemRegistry();
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));

        StethLSTCalculator calculator = new StethLSTCalculator(systemRegistry);
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: STETH_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        assertEq(calculator.calculateEthPerToken(), expected);
    }
}
