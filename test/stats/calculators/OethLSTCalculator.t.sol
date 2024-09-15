// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { OethLSTCalculator } from "src/stats/calculators/OethLSTCalculator.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { OETH_MAINNET, WOETH_MAINNET, TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { Roles } from "src/libs/Roles.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";

contract OethLSTCalculatorTests is Test {
    AccessController private _accessController;
    OethLSTCalculator private _calculator;

    event OsEthPriceOracleSet(address newOracle);

    function setUp() public {
        _setUp(20_713_650);
    }

    function test_calculateEthPerToken_MatchesWrappedConvertToAssets() public {
        uint256 woethVal = IERC4626(WOETH_MAINNET).convertToAssets(1e18);
        uint256 calculatorVal = _calculator.calculateEthPerToken();

        assertApproxEqAbs(woethVal, calculatorVal, 1e4, "val");
    }

    function test_usePriceAsDiscount_IsTrue() public {
        assertEq(_calculator.usePriceAsDiscount(), true, "usePriceAsDiscount");
    }

    function _setUp(uint256 targetBlock) private returns (OethLSTCalculator) {
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, OETH_MAINNET),
            abi.encode(1e18)
        );

        _calculator = OethLSTCalculator(Clones.clone(address(new OethLSTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);

        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: OETH_MAINNET });
        _calculator.initialize(dependantAprs, abi.encode(initData));

        return _calculator;
    }
}
