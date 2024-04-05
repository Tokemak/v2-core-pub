// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";

import { OsethLSTCalculator } from "src/stats/calculators/OsethLSTCalculator.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";

contract DeployOsethCalculator is BaseScript {
    // https://github.com/stakewise/v3-core/blob/5bf378de95c0f51430d6fc7f6b2fc8733a416d3a/deployments/mainnet.json#L13
    address internal constant STAKEWISE_OSETH_PRICE_ORACLE = 0x8023518b2192FB5384DAdc596765B3dD1cdFe471;

    // https://docs.redstone.finance/docs/smart-contract-devs/price-feeds
    address internal constant REDSTONE_OSETH_PRICE_FEED = 0x66ac817f997Efd114EDFcccdce99F3268557B32C;

    bytes32 internal osEthTemplateId = keccak256("oseth");

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);
        vm.startBroadcast(privateKey);

        // Register osETH
        RedstoneOracle oracle = RedstoneOracle(constants.sys.subOracles.redStone);
        oracle.registerOracle(
            constants.tokens.osEth,
            IAggregatorV3Interface(REDSTONE_OSETH_PRICE_FEED),
            BaseOracleDenominations.Denomination.ETH,
            1 days
        );
        RootPriceOracle rootPriceOracle = RootPriceOracle(address(systemRegistry.rootPriceOracle()));
        rootPriceOracle.registerMapping(constants.tokens.osEth, oracle);

        // Setup Template
        StatsCalculatorFactory statsCalcFactory = StatsCalculatorFactory(
            address(StatsCalculatorRegistry(address(systemRegistry.statsCalculatorRegistry())).factory())
        );

        OsethLSTCalculator template = new OsethLSTCalculator(systemRegistry);
        statsCalcFactory.registerTemplate(osEthTemplateId, address(template));

        // Create Calculator from Template
        LSTCalculatorBase.InitData memory initData =
            LSTCalculatorBase.InitData({ lstTokenAddress: constants.tokens.osEth });
        OsethLSTCalculator.OsEthInitData memory osEthInitData = OsethLSTCalculator.OsEthInitData({
            priceOracle: STAKEWISE_OSETH_PRICE_ORACLE,
            baseInitData: abi.encode(initData)
        });
        bytes memory encodedInitData = abi.encode(osEthInitData);
        address calculatorAddress = statsCalcFactory.create(osEthTemplateId, new bytes32[](0), encodedInitData);

        console.log(string.concat("OsethLSTCalculator Address: "), calculatorAddress);

        vm.stopBroadcast();
    }
}
