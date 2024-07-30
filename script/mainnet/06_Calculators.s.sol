// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-states-count,max-line-length

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";

import { AuraCalculator } from "src/stats/calculators/AuraCalculator.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";
import { BalancerComposableStablePoolCalculator } from
    "src/stats/calculators/BalancerComposableStablePoolCalculator.sol";
import { BalancerMetaStablePoolCalculator } from "src/stats/calculators/BalancerMetaStablePoolCalculator.sol";
import { CurveV1PoolNoRebasingStatsCalculator } from "src/stats/calculators/CurveV1PoolNoRebasingStatsCalculator.sol";
import { CurveV1PoolRebasingStatsCalculator } from "src/stats/calculators/CurveV1PoolRebasingStatsCalculator.sol";
import { CurveV1PoolRebasingLockedStatsCalculator } from
    "src/stats/calculators/CurveV1PoolRebasingLockedStatsCalculator.sol";
import { CurveV2PoolNoRebasingStatsCalculator } from "src/stats/calculators/CurveV2PoolNoRebasingStatsCalculator.sol";

import { CurvePoolRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolRebasingCalculatorBase.sol";
import { CurvePoolNoRebasingCalculatorBase } from "src/stats/calculators/base/CurvePoolNoRebasingCalculatorBase.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";

import { CbethLSTCalculator } from "src/stats/calculators/CbethLSTCalculator.sol";
import { RethLSTCalculator } from "src/stats/calculators/RethLSTCalculator.sol";
import { StethLSTCalculator } from "src/stats/calculators/StethLSTCalculator.sol";
import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";
import { OsethLSTCalculator } from "src/stats/calculators/OsethLSTCalculator.sol";
import { SwethLSTCalculator } from "src/stats/calculators/SwethLSTCalculator.sol";

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { Stats } from "src/stats/Stats.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract Calculators is Script {
    Constants.Values public constants;

    // Incentive Template Ids
    bytes32 internal auraTemplateId = keccak256("incentive-aura");
    bytes32 internal convexTemplateId = keccak256("incentive-convex");

    // DEX Template Ids
    bytes32 internal balCompTemplateId = keccak256("dex-balComp");
    bytes32 internal balMetaTemplateId = keccak256("dex-balMeta");
    bytes32 internal curveNRTemplateId = keccak256("dex-curveNoRebasing");
    bytes32 internal curveRTemplateId = keccak256("dex-curveRebasing");
    bytes32 internal curveRLockedTemplateId = keccak256("dex-curveRebasingLocked");
    bytes32 internal curveV2NRTemplateId = keccak256("dex-curveV2NoRebasing");

    // LST Template Ids
    bytes32 internal cbEthLstTemplateId = keccak256("lst-cbeth");
    bytes32 internal rEthLstTemplateId = keccak256("lst-reth");
    bytes32 internal stEthLstTemplateId = keccak256("lst-steth");
    bytes32 internal proxyLstTemplateId = keccak256("lst-proxy");
    bytes32 internal osEthLstTemplateId = keccak256("lst-oseth");
    bytes32 internal swethLstTemplateId = keccak256("lst-sweth");

    // Incentive Templates
    AuraCalculator public auraTemplate;
    ConvexCalculator public convexTemplate;

    // DEX Templates
    BalancerComposableStablePoolCalculator public balCompTemplate;
    BalancerMetaStablePoolCalculator public balMetaTemplate;
    CurveV1PoolNoRebasingStatsCalculator public curveNRTemplate;
    CurveV1PoolRebasingStatsCalculator public curveRTemplate;
    CurveV1PoolRebasingLockedStatsCalculator public curveRLockedTemplate;
    CurveV2PoolNoRebasingStatsCalculator public curveV2NRTemplate;

    // LST Templates
    CbethLSTCalculator public cbEthLstTemplate;
    RethLSTCalculator public rEthLstTemplate;
    StethLSTCalculator public stEthLstTemplate;
    ProxyLSTCalculator public proxyLstTemplate;
    OsethLSTCalculator public osEthLstTemplate;
    SwethLSTCalculator public swethLstTemplate;

    // LST Calculators
    IStatsCalculator public cbEthLstCalculator;
    IStatsCalculator public rEthLstCalculator;
    IStatsCalculator public stEthLstCalculator;
    IStatsCalculator public wstEthLstCalculator;
    IStatsCalculator public osEthLstCalculator;
    IStatsCalculator public swEthLstCalculator;

    // DEX Calculators
    IStatsCalculator public curveStEthEthOriginalCalculator;
    IStatsCalculator public curveStEthEthNgCalculator;
    IStatsCalculator public curveCbEthEthCalculator;
    IStatsCalculator public curveOsEthRethCalculator;
    IStatsCalculator public curveRethWstEthCalculator;

    IStatsCalculator public balancerWstEthWethCalculator;
    IStatsCalculator public balancerRethWethCalculator;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        deployTemplates();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        deployLsts();
        deployCurvePools();
        deployBalancerPools();
        deployCurveConvex();
        deployBalancerAura();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function deployTemplates() private {
        auraTemplate = new AuraCalculator(constants.sys.systemRegistry, constants.ext.auraBooster);
        registerAndOutput("Aura Template", auraTemplate, auraTemplateId);

        convexTemplate = new ConvexCalculator(constants.sys.systemRegistry, constants.ext.convexBooster);
        registerAndOutput("Convex Template", convexTemplate, convexTemplateId);

        balCompTemplate = new BalancerComposableStablePoolCalculator(
            constants.sys.systemRegistry, address(constants.ext.balancerVault)
        );
        registerAndOutput("Balancer Comp Template", balCompTemplate, balCompTemplateId);

        balMetaTemplate =
            new BalancerMetaStablePoolCalculator(constants.sys.systemRegistry, address(constants.ext.balancerVault));
        registerAndOutput("Balancer Meta Template", balMetaTemplate, balMetaTemplateId);

        curveNRTemplate = new CurveV1PoolNoRebasingStatsCalculator(constants.sys.systemRegistry);
        registerAndOutput("Curve No Rebasing Template", curveNRTemplate, curveNRTemplateId);

        curveRTemplate = new CurveV1PoolRebasingStatsCalculator(constants.sys.systemRegistry);
        registerAndOutput("Curve Rebasing Template", curveRTemplate, curveRTemplateId);

        curveRLockedTemplate = new CurveV1PoolRebasingLockedStatsCalculator(constants.sys.systemRegistry);
        registerAndOutput("Curve Rebasing Locked Template", curveRLockedTemplate, curveRLockedTemplateId);

        curveV2NRTemplate = new CurveV2PoolNoRebasingStatsCalculator(constants.sys.systemRegistry);
        registerAndOutput("Curve V2 No Rebasing Template", curveV2NRTemplate, curveV2NRTemplateId);

        cbEthLstTemplate = new CbethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("cbETH LST Template", cbEthLstTemplate, cbEthLstTemplateId);

        rEthLstTemplate = new RethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("rETH LST Template", rEthLstTemplate, rEthLstTemplateId);

        stEthLstTemplate = new StethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("stETH LST Template", stEthLstTemplate, stEthLstTemplateId);

        proxyLstTemplate = new ProxyLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("Proxy LST Template", proxyLstTemplate, proxyLstTemplateId);

        osEthLstTemplate = new OsethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("osETH LST Template", osEthLstTemplate, osEthLstTemplateId);

        swethLstTemplate = new SwethLSTCalculator(constants.sys.systemRegistry);
        registerAndOutput("swETH LST Template", swethLstTemplate, swethLstTemplateId);
    }

    function deployLsts() internal {
        cbEthLstCalculator = IStatsCalculator(_setupLSTCalculatorBase(cbEthLstTemplateId, constants.tokens.cbEth));
        rEthLstCalculator = IStatsCalculator(_setupLSTCalculatorBase(rEthLstTemplateId, constants.tokens.rEth));
        stEthLstCalculator = IStatsCalculator(_setupLSTCalculatorBase(stEthLstTemplateId, constants.tokens.stEth));
        wstEthLstCalculator = IStatsCalculator(
            _setupProxyLSTCalculator("wstEth", constants.tokens.wstEth, address(stEthLstCalculator), false)
        );
        osEthLstCalculator = IStatsCalculator(_setupOsEthLSTCalculator());
        swEthLstCalculator = IStatsCalculator(_setupLSTCalculatorBase(swethLstTemplateId, constants.tokens.swEth));
    }

    function deployCurvePools() internal {
        bytes32[] memory e = new bytes32[](2);
        e[0] = Stats.NOOP_APR_ID;
        e[1] = stEthLstCalculator.getAprId();

        curveStEthEthOriginalCalculator = IStatsCalculator(
            _setupCurvePoolRebasingCalculatorBase(
                "Curve stETH/ETH Original", curveRTemplateId, e, 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 1
            )
        );

        curveStEthEthNgCalculator = IStatsCalculator(
            _setupCurvePoolRebasingCalculatorBase(
                "Curve stETH/ETH ng", curveRLockedTemplateId, e, 0x21E27a5E5513D6e65C4f830167390997aA84843a, 1
            )
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = cbEthLstCalculator.getAprId();
        curveCbEthEthCalculator = IStatsCalculator(
            _setupCurvePoolNoRebasingCalculatorBase(
                "Curve cbETH/ETH Pool", curveV2NRTemplateId, e, 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A
            )
        );

        e[0] = osEthLstCalculator.getAprId();
        e[1] = rEthLstCalculator.getAprId();
        curveOsEthRethCalculator = IStatsCalculator(
            _setupCurvePoolNoRebasingCalculatorBase(
                "Curve osETH/rETH Pool", curveNRTemplateId, e, 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d
            )
        );

        e[0] = rEthLstCalculator.getAprId();
        e[1] = wstEthLstCalculator.getAprId();
        curveRethWstEthCalculator = IStatsCalculator(
            _setupCurvePoolNoRebasingCalculatorBase(
                "Curve rETH/wstETH Pool", curveNRTemplateId, e, 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08
            )
        );
    }

    function deployBalancerPools() internal {
        bytes32[] memory e = new bytes32[](2);

        e[0] = wstEthLstCalculator.getAprId();
        e[1] = Stats.NOOP_APR_ID;
        balancerWstEthWethCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                "Balancer wstETH/WETH Pool", balMetaTemplateId, e, 0x32296969Ef14EB0c6d29669C550D4a0449130230
            )
        );

        e[0] = rEthLstCalculator.getAprId();
        e[1] = Stats.NOOP_APR_ID;
        balancerRethWethCalculator = IStatsCalculator(
            _setupBalancerCalculator(
                "Balancer rETH/WETH Pool", balMetaTemplateId, e, 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276
            )
        );
    }

    function deployBalancerAura() internal {
        address balancerWstEthWethPool = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        address auraWstEthWethRewarder = 0x59D66C58E83A26d6a0E35114323f65c3945c89c1;
        _setupIncentiveCalculatorBase(
            "Aura + Balancer wstETH/WETH",
            auraTemplateId,
            balancerWstEthWethCalculator,
            constants.tokens.aura,
            auraWstEthWethRewarder,
            balancerWstEthWethPool,
            balancerWstEthWethPool
        );

        address balancerRethWethPool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        address auraRethWethRewarder = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;
        _setupIncentiveCalculatorBase(
            "Aura + Balancer rETH/WETH",
            auraTemplateId,
            balancerRethWethCalculator,
            constants.tokens.aura,
            auraRethWethRewarder,
            balancerRethWethPool,
            balancerRethWethPool
        );
    }

    function deployCurveConvex() internal {
        deployCurveConvexSet1();
        deployCurveConvexSet2();
    }

    function deployCurveConvexSet1() internal {
        // stETH/ETH Original
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address convexStEthOriginalRewarder = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;
        _setupIncentiveCalculatorBase(
            "Convex + Curve stETH/ETH Original",
            convexTemplateId,
            curveStEthEthOriginalCalculator,
            constants.tokens.cvx,
            convexStEthOriginalRewarder,
            curveStEthOriginalLpToken,
            curveStEthOriginalPool
        );

        // stETH/ETH ng
        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address convexStEthNgRewarder = 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8;
        _setupIncentiveCalculatorBase(
            "Convex + Curve stETH/ETH NG",
            convexTemplateId,
            curveStEthEthNgCalculator,
            constants.tokens.cvx,
            convexStEthNgRewarder,
            curveStEthNgLpToken,
            curveStEthNgPool
        );

        // cbETH/ETH
        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;
        address convexV2cbEthEthRewarder = 0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699;
        _setupIncentiveCalculatorBase(
            "Convex + Curve V2 cbETH/ETH",
            convexTemplateId,
            curveCbEthEthCalculator,
            constants.tokens.cvx,
            convexV2cbEthEthRewarder,
            curveV2cbEthEthLpToken,
            curveV2cbEthEthPool
        );

        // osEth/rETH
        address curveOsEthRethPool = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        address curveOsEthRethLpToken = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        address curveOsEthRethRewarder = 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e;
        _setupIncentiveCalculatorBase(
            "Convex + Curve osETH/rETH",
            convexTemplateId,
            curveOsEthRethCalculator,
            constants.tokens.cvx,
            curveOsEthRethRewarder,
            curveOsEthRethLpToken,
            curveOsEthRethPool
        );
    }

    function deployCurveConvexSet2() internal {
        // rETH/wstETH
        address curveRethWstethPool = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveRethWstethLpToken = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address convexRethWstethRewarder = 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc;
        _setupIncentiveCalculatorBase(
            "Convex + Curve rETH/wstETH",
            convexTemplateId,
            curveRethWstEthCalculator,
            constants.tokens.cvx,
            convexRethWstethRewarder,
            curveRethWstethLpToken,
            curveRethWstethPool
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

    function _setupCurvePoolNoRebasingCalculatorBase(
        string memory name,
        bytes32 aprTemplateId,
        bytes32[] memory dependentAprIds,
        address poolAddress
    ) internal returns (address) {
        CurvePoolNoRebasingCalculatorBase.InitData memory initData =
            CurvePoolNoRebasingCalculatorBase.InitData({ poolAddress: poolAddress });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, dependentAprIds, encodedInitData);

        outputDexCalculator(name, addr);

        return addr;
    }

    function _setupCurvePoolRebasingCalculatorBase(
        string memory name,
        bytes32 aprTemplateId,
        bytes32[] memory dependentAprIds,
        address poolAddress,
        uint256 rebasingTokenIdx
    ) internal returns (address) {
        CurvePoolRebasingCalculatorBase.InitData memory initData =
            CurvePoolRebasingCalculatorBase.InitData({ poolAddress: poolAddress, rebasingTokenIdx: rebasingTokenIdx });
        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, dependentAprIds, encodedInitData);

        outputDexCalculator(name, addr);

        return addr;
    }

    function _setupLSTCalculatorBase(bytes32 aprTemplateId, address lstTokenAddress) internal returns (address) {
        LSTCalculatorBase.InitData memory initData = LSTCalculatorBase.InitData({ lstTokenAddress: lstTokenAddress });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, e, encodedInitData);
        outputCalculator(IERC20Metadata(lstTokenAddress).symbol(), addr);

        return addr;
    }

    function _setupOsEthLSTCalculator() internal returns (address) {
        // https://github.com/stakewise/v3-core/blob/5bf378de95c0f51430d6fc7f6b2fc8733a416d3a/deployments/mainnet.json#L13
        address stakeWiseOsEthPriceOracle = 0x8023518b2192FB5384DAdc596765B3dD1cdFe471;

        LSTCalculatorBase.InitData memory initData =
            LSTCalculatorBase.InitData({ lstTokenAddress: constants.tokens.osEth });
        OsethLSTCalculator.OsEthInitData memory osEthInitData = OsethLSTCalculator.OsEthInitData({
            priceOracle: stakeWiseOsEthPriceOracle,
            baseInitData: abi.encode(initData)
        });
        bytes memory encodedInitData = abi.encode(osEthInitData);
        address addr = constants.sys.statsCalcFactory.create(osEthLstTemplateId, new bytes32[](0), encodedInitData);
        outputCalculator("osETH", addr);
        return addr;
    }

    function _setupProxyLSTCalculator(
        string memory name,
        address lstTokenAddress,
        address statsCalculator,
        bool isRebasing
    ) internal returns (address) {
        ProxyLSTCalculator.InitData memory initData = ProxyLSTCalculator.InitData({
            lstTokenAddress: lstTokenAddress,
            statsCalculator: statsCalculator,
            isRebasing: isRebasing
        });
        bytes memory encodedInitData = abi.encode(initData);
        bytes32[] memory e = new bytes32[](0);

        address addr = constants.sys.statsCalcFactory.create(proxyLstTemplateId, e, encodedInitData);
        outputCalculator(name, addr);
        return addr;
    }

    function outputCalculator(string memory name, address addr) internal {
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
