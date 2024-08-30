// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { BridgedLSTCalculator } from "src/stats/calculators/bridged/BridgedLSTCalculator.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReceivingRouter } from "src/receivingRouter/ReceivingRouter.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";

contract StatBridging is Script {
    Constants.Values public constants;

    bytes32 internal bridgedLstTemplateId = keccak256("lst-bridged");

    uint64 public ccipMainnetChainSelector = 5_009_297_550_715_157_269;

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.RECEIVING_ROUTER_MANAGER, owner);

        address[] memory msgReceivers = new address[](1);
        msgReceivers[0] = address(0xEa574296d6E543264CB25f68D77e522AC2ae4d85); //wsEthCalculator Base
        ReceivingRouter(constants.sys.systemRegistry.receivingRouter()).setMessageReceivers(
            0x05710c444530E55241516a4d6B6c5dd8E5508B15, //stEthLstCalculator on Mainnet
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        vm.stopBroadcast();
    }

    function _setupBridgedLSTCalculatorBase(
        bytes32 aprTemplateId,
        address lstTokenAddress,
        address sourceTokenAddress,
        bool usePriceAsDiscount,
        address ethPerTokenStore
    ) internal returns (address) {
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: lstTokenAddress,
            sourceTokenAddress: sourceTokenAddress,
            usePriceAsDiscount: usePriceAsDiscount,
            ethPerTokenStore: ethPerTokenStore
        });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, e, encodedInitData);
        outputCalculator(IERC20Metadata(lstTokenAddress).symbol(), addr);

        return addr;
    }

    function registerAndOutput(string memory name, BaseStatsCalculator template, bytes32 id) private {
        constants.sys.statsCalcFactory.registerTemplate(id, address(template));
        console.log("-------------------------");
        console.log(string.concat(name, ": "), address(template));
        console.logBytes32(id);
        console.log("-------------------------");
    }

    function outputCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " LST Calculator address: "), addr);
        // console.log(
        //     string.concat(name, " Last Snapshot Timestamp: "),
        // ProxyLSTCalculator(addr).current().lastSnapshotTimestamp
        // );
        console.log("-----------------");
        vm.startBroadcast();
    }
}
