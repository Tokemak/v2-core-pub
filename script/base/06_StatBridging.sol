// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { EthPerTokenStore } from "src/stats/calculators/bridged/EthPerTokenStore.sol";
import { BridgedLSTCalculator } from "src/stats/calculators/bridged/BridgedLSTCalculator.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
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

        Constants.Tokens memory mainnetTokens = Constants.getMainnetTokens();

        ReceivingRouter receivingRouter =
            new ReceivingRouter(address(constants.ext.ccipRouter), constants.sys.systemRegistry);
        constants.sys.systemRegistry.setReceivingRouter(address(receivingRouter));
        console.log("ReceivingRouter: ", address(receivingRouter));

        constants.sys.accessController.grantRole(Roles.RECEIVING_ROUTER_MANAGER, owner);

        // Mainnet Gen 2 Message Proxy
        receivingRouter.setSourceChainSenders(ccipMainnetChainSelector, 0x52bF30EA5870c66Ab2b5aF3E2E9A50E750596eb5, 0);

        EthPerTokenStore store = new EthPerTokenStore(constants.sys.systemRegistry);
        console.log("EthPerTokenStore: ", address(store));

        constants.sys.accessController.grantRole(Roles.STATS_GENERAL_MANAGER, owner);

        store.registerToken(mainnetTokens.rEth);
        store.registerToken(mainnetTokens.cbEth);
        store.registerToken(mainnetTokens.wstEth);

        constants.sys.accessController.revokeRole(Roles.STATS_GENERAL_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        BridgedLSTCalculator bridgedLst = new BridgedLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("Bridged LST Template:", bridgedLst, bridgedLstTemplateId);

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

        IStatsCalculator cbEthLstCalculator = IStatsCalculator(
            _setupBridgedLSTCalculatorBase(
                bridgedLstTemplateId, constants.tokens.cbEth, mainnetTokens.cbEth, false, address(store)
            )
        );
        outputCalculator("CbEth LST", address(cbEthLstCalculator));

        IStatsCalculator wstEthLstCalculator = IStatsCalculator(
            _setupBridgedLSTCalculatorBase(
                bridgedLstTemplateId, constants.tokens.wstEth, mainnetTokens.wstEth, false, address(store)
            )
        );
        outputCalculator("wstEth LST", address(wstEthLstCalculator));

        IStatsCalculator rEthLstCalculator = IStatsCalculator(
            _setupBridgedLSTCalculatorBase(
                bridgedLstTemplateId, constants.tokens.rEth, mainnetTokens.rEth, false, address(store)
            )
        );
        outputCalculator("rEth LST", address(rEthLstCalculator));

        // Route LST APR messages from mainnet to the calculators

        address[] memory msgReceivers = new address[](1);
        msgReceivers[0] = address(cbEthLstCalculator);
        receivingRouter.setMessageReceivers(
            0x059C6005b96ED7a71dD34BFF700800Ddd61A1A38, //cbEthLstCalculator on Mainnet
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        msgReceivers[0] = address(rEthLstCalculator);
        receivingRouter.setMessageReceivers(
            0x1854C26405c83b0bBC741E6C8DF964dEF786C7e2, //rEthLstCalculator on Mainnet
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        msgReceivers[0] = address(wstEthLstCalculator);
        receivingRouter.setMessageReceivers(
            0x612871600a5112F2f8309C294D62C83B7bBE466d, //wstEthLstCalculator on Mainnet
            MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        // Set Eth Per Token Messages
        msgReceivers[0] = address(store);
        receivingRouter.setMessageReceivers(
            0x4a6dc8aFB1167e6e55c022fbC3f38bCd5dCec66c, //EthPerTokenSender on Mainnet
            MessageTypes.LST_BACKING_MESSAGE_TYPE,
            ccipMainnetChainSelector,
            msgReceivers
        );

        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.RECEIVING_ROUTER_MANAGER, owner);

        vm.stopBroadcast();
    }

    function _setupBridgedLSTCalculatorBase(
        bytes32 aprTemplateId,
        address lstTokenAddress,
        address sourceTokenAddress,
        bool usePriceAsBacking,
        address ethPerTokenStore
    ) internal returns (address) {
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: lstTokenAddress,
            sourceTokenAddress: sourceTokenAddress,
            usePriceAsBacking: usePriceAsBacking,
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
