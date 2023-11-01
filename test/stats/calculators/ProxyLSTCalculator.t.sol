// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Stats } from "src/stats/Stats.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { TOKE_MAINNET, WETH_MAINNET, CBETH_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract ProxyLSTCalculatorTest is Test {
    SystemRegistry private _systemRegistry;
    AccessController private _accessController;

    LSTCalculatorHarness private _calculator;
    ProxyLSTCalculator private _proxyCalculator;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));
        _accessController.grantRole(Roles.STATS_SNAPSHOT_ROLE, address(this));

        _calculator = new LSTCalculatorHarness(_systemRegistry);
        _proxyCalculator = new ProxyLSTCalculator(_systemRegistry);
    }

    function test_Revert_WhenSnapshot() public {
        vm.expectRevert(IStatsCalculator.NoSnapshotTaken.selector);
        _proxyCalculator.snapshot();
    }

    function test_shouldSnapshot_IsAlwaysFalse() public {
        bool val = _proxyCalculator.shouldSnapshot();
        assertFalse(val);
    }

    function test_current_Success() public {
        uint24[10] memory discountHistory;
        uint40[5] memory discountTimestampByPercent;
        ILSTStats.LSTStatsData memory stats = ILSTStats.LSTStatsData({
            lastSnapshotTimestamp: 12,
            baseApr: 10,
            discount: 0,
            discountHistory: discountHistory,
            discountTimestampByPercent: discountTimestampByPercent,
            slashingCosts: new uint256[](0),
            slashingTimestamps: new uint256[](0)
        });

        vm.mockCall(address(_calculator), abi.encodeWithSelector(ILSTStats.current.selector), abi.encode(stats));

        bytes32[] memory dependantAprs = new bytes32[](0);
        ProxyLSTCalculator.InitData memory initData = ProxyLSTCalculator.InitData({
            lstTokenAddress: CBETH_MAINNET,
            statsCalculator: address(_calculator),
            isRebasing: true
        });
        _proxyCalculator.initialize(dependantAprs, abi.encode(initData));

        assertTrue(_proxyCalculator.isRebasing());

        ILSTStats.LSTStatsData memory res = _proxyCalculator.current();
        assertEq(res.baseApr, 10);
        assertEq(res.lastSnapshotTimestamp, 12);
    }
}

contract LSTCalculatorHarness is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    function calculateEthPerToken() public pure override returns (uint256) {
        return 0;
    }

    function isRebasing() public pure override returns (bool) {
        return false;
    }
}
