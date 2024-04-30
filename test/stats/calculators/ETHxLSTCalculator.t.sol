// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IETHx } from "src/interfaces/external/stader/IETHx.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ETHxLSTCalculator } from "src/stats/calculators/ETHxLSTCalculator.sol";
import { IStaderOracle } from "src/interfaces/external/stader/IStaderOracle.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { TOKE_MAINNET, WETH_MAINNET, ETHX_MAINNET } from "test/utils/Addresses.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";

// solhint-disable func-name-mixedcase
contract ETHxLSTCalculatorTest is Test {
    function test_calculateEthPerToken_CorrectStandardCalculation() public {
        ETHxLSTCalculator calculator = _setUp(19_570_655);

        assertEq(calculator.calculateEthPerToken(), 1_026_062_087_578_939_158, "ethPerToken");
    }

    function test_calculateEthPerToken_CanHandleAZeroSupply() public {
        ETHxLSTCalculator calculator = _setUp(19_570_655);

        IStaderOracle oracle = IETHx(calculator.lstTokenAddress()).staderConfig().getStaderOracle();
        IStaderOracle.ExchangeRate memory mockRate = IStaderOracle.ExchangeRate({
            reportingBlockNumber: 19_562_400,
            totalETHBalance: 125_031_355_676_287_647_446_811,
            totalETHXSupply: 0
        });
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IStaderOracle.getExchangeRate.selector), abi.encode(mockRate)
        );

        assertEq(calculator.calculateEthPerToken(), 1e18, "ethPerToken");
    }

    function test_IsRebasing_False() public {
        ETHxLSTCalculator calculator = _setUp(19_570_655);

        assertEq(calculator.isRebasing(), false, "isRebasing");
    }

    function _setUp(uint256 targetBlock) private returns (ETHxLSTCalculator) {
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
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, ETHX_MAINNET),
            abi.encode(1.022651e18)
        );

        ETHxLSTCalculator calculator = ETHxLSTCalculator(Clones.clone(address(new ETHxLSTCalculator(systemRegistry))));
        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: ETHX_MAINNET });
        calculator.initialize(dependantAprs, abi.encode(initData));

        return calculator;
    }

    function checkEthPerToken(uint256 targetBlock, uint256 expected) private { }
}
