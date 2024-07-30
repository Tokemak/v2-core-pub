// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Stats } from "src/stats/Stats.sol";
import { Roles } from "src/libs/Roles.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { AuraL2Calculator } from "src/stats/calculators/AuraL2Calculator.sol";
import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerComposableStablePoolCalculator } from
    "src/stats/calculators/BalancerComposableStablePoolCalculator.sol";

contract Calculators is Script {
    Constants.Values public constants;

    // Incentive Template Ids
    bytes32 internal auraTemplateId = keccak256("incentive-aura");
    bytes32 internal convexTemplateId = keccak256("incentive-convex");

    // DEX Template Ids
    bytes32 internal balCompTemplateId = keccak256("dex-balComp");

    // Incentive Templates
    AuraL2Calculator public auraTemplate;

    // DEX Templates
    BalancerComposableStablePoolCalculator public balCompTemplate;

    IStatsCalculator public balancerRethWethCalculator;
    IStatsCalculator public balancerCbethWethCalculator;

    function run() external {
        constants = Constants.get(Systems.LST_GEN1_BASE);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        deployTemplates();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        deployBalancerPools();
        deployBalancerAura();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function deployTemplates() private {
        auraTemplate = new AuraL2Calculator(constants.sys.systemRegistry, constants.ext.auraBooster);
        registerAndOutput("Aura Template", auraTemplate, auraTemplateId);

        balCompTemplate = new BalancerComposableStablePoolCalculator(
            constants.sys.systemRegistry, address(constants.ext.balancerVault)
        );
        registerAndOutput("Balancer Comp Template", balCompTemplate, balCompTemplateId);
    }

    function deployBalancerPools() internal {
        bytes32[] memory e = new bytes32[](2);

        e[0] = Stats.NOOP_APR_ID;
        e[1] = constants.sys.statsCalcRegistry.getCalculator(Stats.generateRawTokenIdentifier(constants.tokens.rEth))
            .getAprId();
        balancerRethWethCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                "Balancer WETH/rETH Pool", balCompTemplateId, e, 0xC771c1a5905420DAEc317b154EB13e4198BA97D0
            )
        );

        e[0] = constants.sys.statsCalcRegistry.getCalculator(Stats.generateRawTokenIdentifier(constants.tokens.cbEth))
            .getAprId();
        e[1] = Stats.NOOP_APR_ID;
        balancerCbethWethCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                "Balancer cbETH/WETH Pool", balCompTemplateId, e, 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6
            )
        );
    }

    function deployBalancerAura() internal {
        address balancerRethWethPool = 0xC771c1a5905420DAEc317b154EB13e4198BA97D0;
        address balancerRethWethRewarder = 0xcCAC11368BDD522fc4DD23F98897712391ab1E00;
        deployBalAuraCalculator("Aura + Balancer WETH/rETH", balancerRethWethPool, balancerRethWethRewarder);

        address balancerCbethWethPool = 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6;
        address balancerCbethWethRewarder = 0x8dB6A97AeEa09F37b45C9703c3542087151aAdD5;
        deployBalAuraCalculator("Aura + Balancer cbETH/WETH", balancerCbethWethPool, balancerCbethWethRewarder);
    }

    function deployBalAuraCalculator(string memory name, address poolAddress, address auraRewarder) internal {
        _setupIncentiveCalculatorBase(
            name,
            auraTemplateId,
            constants.sys.statsCalcRegistry.getCalculator(Stats.generateBalancerPoolIdentifier(poolAddress)),
            constants.tokens.aura,
            auraRewarder,
            poolAddress,
            poolAddress
        );
    }

    function _setupIncentiveCalculatorBase(
        string memory name,
        bytes32 aprTemplateId,
        IStatsCalculator poolCalculator,
        address platformToken,
        address rewarder,
        address lpToken,
        address pool
    ) internal returns (address) {
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: rewarder,
            platformToken: platformToken,
            underlyerStats: address(poolCalculator),
            lpToken: lpToken,
            pool: pool
        });

        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, new bytes32[](0), encodedInitData);

        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " Incentive Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("-----------------");
        vm.startBroadcast();

        return addr;
    }

    function _setupBalancerCalculator(
        string memory name,
        bytes32 aprTemplateId,
        bytes32[] memory dependentAprIds,
        address poolAddress
    ) internal returns (address) {
        BalancerStablePoolCalculatorBase.InitData memory initData =
            BalancerStablePoolCalculatorBase.InitData({ poolAddress: poolAddress });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, dependentAprIds, encodedInitData);

        outputDexCalculator(name, addr);

        return addr;
    }

    function outputCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " LST Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), ProxyLSTCalculator(addr).current().lastSnapshotTimestamp
        );
        console.log("-----------------");
        vm.startBroadcast();
    }

    function outputDexCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " DEX Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("-----------------");
        vm.startBroadcast();
    }

    function registerAndOutput(string memory name, BaseStatsCalculator template, bytes32 id) private {
        constants.sys.statsCalcFactory.registerTemplate(id, address(template));
        console.log("-------------------------");
        console.log(string.concat(name, ": "), address(template));
        console.logBytes32(id);
        console.log("-------------------------");
    }
}
