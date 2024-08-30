// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { Constants } from "../utils/Constants.sol";

import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";

import { CurvePoolRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolRebasingCalculatorBase.sol";
import { CurvePoolNoRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolNoRebasingCalculatorBase.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";

import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { BridgedLSTCalculator } from "src/stats/calculators/bridged/BridgedLSTCalculator.sol";

contract Calculators {
    VmSafe private vm;

    struct ProxyLstCalculatorSetup {
        string name;
        bytes32 aprTemplateId;
        address lstTokenAddress;
        address statsCalculator;
        bool usePriceAsDiscount;
    }

    struct IncentiveCalcBaseSetup {
        string name;
        bytes32 aprTemplateId;
        IStatsCalculator poolCalculator;
        address platformToken;
        address rewarder;
        address lpToken;
        address pool;
    }

    struct BalancerCalcSetup {
        string name;
        bytes32 aprTemplateId;
        bytes32[] dependentAprIds;
        address poolAddress;
    }

    struct CurveNoRebasingSetup {
        string name;
        bytes32 aprTemplateId;
        bytes32[] dependentAprIds;
        address poolAddress;
    }

    struct CurveRebasingSetup {
        string name;
        bytes32 aprTemplateId;
        bytes32[] dependentAprIds;
        address poolAddress;
        uint256 rebasingTokenIdx;
    }

    struct LSTCalcSetup {
        bytes32 aprTemplateId;
        address lstTokenAddress;
    }

    struct AeroDexSetup {
        string name;
        bytes32 aprTemplateId;
        bytes32[] dependentAprIds;
        address poolAddress;
        address gaugeAddress;
    }

    constructor(VmSafe _vm) {
        vm = _vm;
    }

    // function _setupAeroIncentiveCalculator(
    //     Constants.Values memory constants,
    //     AeroIncentiveSetup memory args
    // ) internal returns (address) {
    //     AerodromeStakingIncentiveCalculator.InitData memory initData = AerodromeStakingIncentiveCalculator.InitData({
    //         poolAddress: args.poolAddress,
    //         gaugeAddress: args.gaugeAddress,
    //         underlyerStats: args.dexCalculator
    //     });

    //     bytes memory encodedInitData = abi.encode(initData);

    //     address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, new bytes32[](0), encodedInitData);

    //     vm.stopBroadcast();
    //     console.log("");
    //     console.log(string.concat(args.name, " Aero Incentive Calculator address: "), addr);
    //     console.log(
    //         string.concat(args.name, " Last Snapshot Timestamp: "),
    // IDexLSTStats(addr).current().lastSnapshotTimestamp
    //     );
    //     console.log("");
    //     vm.startBroadcast();

    //     return addr;
    // }

    function _setupIncentiveCalculatorBase(
        Constants.Values memory constants,
        IncentiveCalcBaseSetup memory args
    ) internal returns (address) {
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: args.rewarder,
            platformToken: args.platformToken,
            underlyerStats: address(args.poolCalculator),
            lpToken: args.lpToken,
            pool: args.pool
        });

        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, new bytes32[](0), encodedInitData);

        vm.stopBroadcast();
        console.log("");
        console.log(string.concat(args.name, " Incentive Calculator address: "), addr);
        console.log(
            string.concat(args.name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("");
        vm.startBroadcast();

        return addr;
    }

    // function _setupAeroDexCalculator(
    //     Constants.Values memory constants,
    //     AeroDexSetup memory args
    // ) internal returns (address) {
    //     AerodromeStakingDexCalculator.InitData memory initData =
    //         AerodromeStakingDexCalculator.InitData({ poolAddress: args.poolAddress });
    //     bytes memory encodedInitData = abi.encode(initData);

    //     address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, args.dependentAprIds,
    // encodedInitData);

    //     outputDexCalculator(args.name, addr);

    //     return addr;
    // }

    function _setupBalancerCalculator(
        Constants.Values memory constants,
        BalancerCalcSetup memory args
    ) internal returns (address) {
        BalancerStablePoolCalculatorBase.InitData memory initData =
            BalancerStablePoolCalculatorBase.InitData({ poolAddress: args.poolAddress });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, args.dependentAprIds, encodedInitData);

        outputDexCalculator(args.name, addr);

        return addr;
    }

    function _setupCurvePoolNoRebasingCalculatorBase(
        Constants.Values memory constants,
        CurveNoRebasingSetup memory args
    ) internal returns (address) {
        CurvePoolNoRebasingCalculatorBase.InitData memory initData =
            CurvePoolNoRebasingCalculatorBase.InitData({ poolAddress: args.poolAddress });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, args.dependentAprIds, encodedInitData);

        outputDexCalculator(args.name, addr);

        return addr;
    }

    function _setupCurvePoolRebasingCalculatorBase(
        Constants.Values memory constants,
        CurveRebasingSetup memory args
    ) internal returns (address) {
        CurvePoolRebasingCalculatorBase.InitData memory initData = CurvePoolRebasingCalculatorBase.InitData({
            poolAddress: args.poolAddress,
            rebasingTokenIdx: args.rebasingTokenIdx
        });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, args.dependentAprIds, encodedInitData);

        outputDexCalculator(args.name, addr);

        return addr;
    }

    struct BridgedLSTCalculatorSetup {
        bytes32 aprTemplateId;
        address lstTokenAddress;
        address sourceTokenAddress;
        bool usePriceAsDiscount;
        address ethPerTokenStore;
    }

    function _setupBridgedLSTCalculatorBase(
        Constants.Values memory constants,
        BridgedLSTCalculatorSetup memory args
    ) internal returns (address) {
        BridgedLSTCalculator.L2InitData memory initData = BridgedLSTCalculator.L2InitData({
            lstTokenAddress: args.lstTokenAddress,
            sourceTokenAddress: args.sourceTokenAddress,
            usePriceAsDiscount: args.usePriceAsDiscount,
            ethPerTokenStore: args.ethPerTokenStore
        });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, e, encodedInitData);
        outputCalculator(IERC20Metadata(args.lstTokenAddress).symbol(), addr);

        return addr;
    }

    function _setupLSTCalculatorBase(
        Constants.Values memory constants,
        LSTCalcSetup memory args
    ) internal returns (address) {
        LSTCalculatorBase.InitData memory initData =
            LSTCalculatorBase.InitData({ lstTokenAddress: args.lstTokenAddress });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, e, encodedInitData);
        outputCalculator(IERC20Metadata(args.lstTokenAddress).symbol(), addr);

        return addr;
    }

    function _setupProxyLSTCalculator(
        Constants.Values memory constants,
        ProxyLstCalculatorSetup memory args
    ) internal returns (address) {
        ProxyLSTCalculator.InitData memory initData = ProxyLSTCalculator.InitData({
            lstTokenAddress: args.lstTokenAddress,
            statsCalculator: args.statsCalculator,
            usePriceAsDiscount: args.usePriceAsDiscount
        });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(args.aprTemplateId, e, encodedInitData);
        outputCalculator(args.name, addr);
        return addr;
    }

    function outputCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("");
        console.log(string.concat(name, " LST Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), ProxyLSTCalculator(addr).current().lastSnapshotTimestamp
        );
        console.log("");
        vm.startBroadcast();
    }

    function outputDexCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("");
        console.log(string.concat(name, " DEX Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("");
        vm.startBroadcast();
    }

    function registerAndOutput(
        Constants.Values memory constants,
        string memory name,
        BaseStatsCalculator template,
        bytes32 id
    ) internal {
        constants.sys.statsCalcFactory.registerTemplate(id, address(template));
        console.log("");
        console.log(string.concat(name, ": "), address(template));
        console.logBytes32(id);
        console.log("");
    }
}
