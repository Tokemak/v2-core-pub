// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ReceivingRouter } from "src/receivingRouter/ReceivingRouter.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";
import { Calculators } from "script/core/Calculators.sol";
import { Oracle } from "script/core/Oracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";

contract StatBridging is Script, Calculators, Oracle {
    Constants.Values public constants;

    bytes32 internal bridgedLstTemplateId = keccak256("lst-bridged");

    uint64 public ccipMainnetChainSelector = 5_009_297_550_715_157_269;

    constructor() Calculators(vm) { }

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        Constants.Tokens memory mainnetTokens = Constants.getMainnetTokens();

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.RECEIVING_ROUTER_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.weEth,
                feedAddress: 0xFC1415403EbB0c693f9a7844b92aD2Ff24775C65,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        IStatsCalculator weEthLstCalculator = IStatsCalculator(
            _setupBridgedLSTCalculatorBase(
                constants,
                BridgedLSTCalculatorSetup({
                    aprTemplateId: bridgedLstTemplateId,
                    lstTokenAddress: constants.tokens.weEth,
                    sourceTokenAddress: mainnetTokens.weEth,
                    isRebasing: false,
                    ethPerTokenStore: address(constants.sys.ethPerTokenStore)
                })
            )
        );

        address[] memory msgReceivers = new address[](1);
        msgReceivers[0] = address(weEthLstCalculator);
        ReceivingRouter(address(constants.sys.systemRegistry.receivingRouter())).setMessageReceivers(
            0x430817253CE0dd85F3bCF5B704A4D266dFE63BBf, //eEthLstCalculator on Mainnet
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.RECEIVING_ROUTER_MANAGER, owner);

        vm.stopBroadcast();
    }
}
