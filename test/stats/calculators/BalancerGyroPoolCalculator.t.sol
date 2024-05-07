// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBalancerGyroPool } from "src/interfaces/external/balancer/IBalancerGyroPool.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { CbethLSTCalculator } from "src/stats/calculators/CbethLSTCalculator.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { BalancerGyroPoolCalculator } from "src/stats/calculators/BalancerGyroPoolCalculator.sol";
import { BAL_VAULT, TOKE_MAINNET, WETH_MAINNET, WSTETH_MAINNET, CBETH_MAINNET } from "test/utils/Addresses.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";

contract BalancerGyroPoolCalculatorTest is Test {
    BalancerGyroPoolCalculator private calculator;

    uint256 internal startBlock = 19_000_000;

    address internal mockCbethWethGyroPool = vm.addr(100);
    bytes32 internal mockCbethWethGyroPoolId = bytes32(uint256(1_235_432_154_321));

    SystemRegistry private systemRegistry;
    AccessController private accessController;
    StatsCalculatorRegistry private statsRegistry;
    StatsCalculatorFactory private statsFactory;
    RootPriceOracle private rootPriceOracle;
    CbethLSTCalculator private mockCbETHCalculator;

    event UpdatedReservesEth(
        uint256 currentTimestamp, uint256 index, uint256 priorReservesEth, uint256 updatedReservesEth
    );

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), startBlock);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));

        statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, CBETH_MAINNET),
            abi.encode(1e18)
        );
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, WETH_MAINNET),
            abi.encode(1e18)
        );

        bytes32[] memory dependantAprs = new bytes32[](0);
        LSTCalculatorBase.InitData memory iData = LSTCalculatorBase.InitData({ lstTokenAddress: CBETH_MAINNET });
        mockCbETHCalculator = CbethLSTCalculator(Clones.clone(address(new CbethLSTCalculator(systemRegistry))));
        mockCbETHCalculator.initialize(dependantAprs, abi.encode(iData));
        vm.mockCall(
            address(mockCbETHCalculator),
            abi.encodeWithSelector(CbethLSTCalculator.calculateEthPerToken.selector),
            abi.encode(101e16)
        );
        vm.prank(address(statsFactory));
        statsRegistry.register(address(mockCbETHCalculator));
    }

    function mockGetPoolTokens(bytes32 poolId, address[] memory tokens, uint256[] memory balances) internal {
        vm.mockCall(
            BAL_VAULT, abi.encodeWithSelector(IVault.getPoolTokens.selector, poolId), abi.encode(tokens, balances)
        );
    }

    function mockGetInvariantDivActualSupply(uint256 value) internal {
        vm.mockCall(
            mockCbethWethGyroPool,
            abi.encodeWithSelector(IBalancerGyroPool.getInvariantDivActualSupply.selector),
            abi.encode(value)
        );
    }

    function getInitData(address poolAddress) internal pure returns (bytes memory) {
        return abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: poolAddress }));
    }

    function successfulInitialize() internal {
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = mockCbETHCalculator.getAprId();
        depAprIds[1] = Stats.NOOP_APR_ID;

        bytes memory initData = getInitData(mockCbethWethGyroPool);
        mockGetInvariantDivActualSupply(25e17);
        mockPoolId(mockCbethWethGyroPoolId);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 100e18;
        balances[1] = 50e18;

        address[] memory tokens = new address[](2);
        tokens[0] = CBETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        mockGetPoolTokens(mockCbethWethGyroPoolId, tokens, balances);

        calculator.initialize(depAprIds, initData);
    }

    function mockPoolId(bytes32 res) internal {
        vm.mockCall(mockCbethWethGyroPool, abi.encodeWithSelector(IBalancerPool.getPoolId.selector), abi.encode(res));
    }

    function testSuccesfulInitialize() public {
        vm.warp(1_705_173_443);
        successfulInitialize();

        assertEq(calculator.poolAddress(), mockCbethWethGyroPool);
        assertEq(calculator.DEX_RESERVE_ALPHA(), 33e16);
        assertEq(calculator.poolId(), mockCbethWethGyroPoolId);
        assertEq(calculator.reserveTokens(0), CBETH_MAINNET);
        assertEq(calculator.reserveTokens(1), WETH_MAINNET);

        assertEq(calculator.lastEthPerShare(0), 101e16); // mocked backing from cbETH calculator
        assertEq(calculator.lastEthPerShare(1), 0); //skipped because of WETH is NO OPP

        assertEq(calculator.reservesEth(0), 0);
        assertEq(calculator.reservesEth(1), 0);

        assertEq(calculator.lastSnapshotTimestamp(), 1_705_173_443);

        assertEq(calculator.lastVirtualPrice(), 25e17);
        assertEq(calculator.feeAprFilterInitialized(), false);
    }

    function testConstructorShouldRevertIfBalancerVaultZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_balancerVault"));
        new TestBalancerCalculator(systemRegistry, address(0));
    }

    function testConstructorShouldSetBalVault() public {
        assertEq(address(calculator.balancerVault()), BAL_VAULT);
    }

    function testInitializeRevertIfPoolAddressIsZero() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "poolAddress"));
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfPoolAddressNotAPoolAddress() public {
        bytes32[] memory depAprIds = new bytes32[](2);
        bytes memory initData = getInitData(vm.addr(431_554));
        vm.expectRevert();
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfPoolHasThreeTokens() public {
        bytes32[] memory depAprIds = new bytes32[](2);

        bytes memory initData = getInitData(address(0x848a5564158d84b8A8fb68ab5D004Fae11619A54));
        // how to structure this
        // vm.expectRevert(abi.encodeWithSelector(BalancerStablePoolCalculatorBase.InvalidPool.selector,
        // "poolAddress"));
        vm.expectRevert();
        calculator.initialize(depAprIds, initData);
    }

    function testInitializeRevertIfWrongGyroInitDataLengths() public {
        bytes32[] memory depAprIds = new bytes32[](3);
        bytes memory initData = getInitData(mockCbethWethGyroPool);
        vm.expectRevert();
        calculator.initialize(depAprIds, initData);
    }

    function testShouldNotSnapshotIfNotReady() public {
        successfulInitialize();
        assertFalse(calculator.shouldSnapshot());

        vm.expectRevert(abi.encodeWithSelector(IStatsCalculator.NoSnapshotTaken.selector));
        calculator.snapshot();
    }

    function testFeeAprSnapshot() public {
        vm.warp(1_705_173_443);
        successfulInitialize();
        vm.warp(block.timestamp + 9 days);
        mockGetInvariantDivActualSupply(26e17);
        // fee filter is initialized
        calculator.snapshot();

        assertEq(calculator.lastVirtualPrice(), 26e17);
        assertEq(calculator.feeAprFilterInitialized(), true);

        assertEq(calculator.lastEthPerShare(0), 101e16); // mocked backing from cbETH calculator
        assertEq(calculator.lastEthPerShare(1), 0); //skipped because of WETH is NO OPP

        assertEq(calculator.reservesEth(0), 100e18);
        assertEq(calculator.reservesEth(1), 50e18);

        assertEq(calculator.feeApr(), 1_622_222_222_222_222_222);

        // Run the next sample through fee filter
        vm.warp(block.timestamp + 1 days);
        mockGetInvariantDivActualSupply(27e17);
        assertEq(calculator.feeAprFilterInitialized(), true);
        // fee filter is initialized
        calculator.snapshot();
        assertEq(calculator.feeApr(), 2_863_846_153_846_153_826);
    }

    function testReservesSnapshot() public {
        vm.warp(1_705_173_443);
        successfulInitialize();
        mockGetInvariantDivActualSupply(26e17);
        // this snapshot should start to update fee apr
        vm.warp(block.timestamp + 10 days);
        vm.mockCall(
            address(mockCbETHCalculator),
            abi.encodeWithSelector(CbethLSTCalculator.calculateEthPerToken.selector),
            abi.encode(105e16) // check that we overwrite lastEthPerShare
        );
        uint256[] memory balances = new uint256[](2);
        balances[0] = 101e18;
        balances[1] = 49e18;
        address[] memory tokens = new address[](2);
        tokens[0] = CBETH_MAINNET;
        tokens[1] = WETH_MAINNET;
        mockGetPoolTokens(mockCbethWethGyroPoolId, tokens, balances);
        vm.expectEmit(true, true, true, true);
        emit UpdatedReservesEth(block.timestamp, 0, 0, 101e18);
        vm.expectEmit(true, true, true, true);
        emit UpdatedReservesEth(block.timestamp, 1, 0, 49e18);
        calculator.snapshot();

        // reserves are updated with initial sample
        assertEq(calculator.reservesEth(0), 101e18);
        assertEq(calculator.reservesEth(1), 49e18);

        // next snapshot
        vm.warp(block.timestamp + 1 days);
        balances[0] = 98e18;
        balances[1] = 52e18;
        mockGetPoolTokens(mockCbethWethGyroPoolId, tokens, balances);
        calculator.snapshot();
        // reserves sample is run through the filter
        assertEq(calculator.reservesEth(0), 100_010_000_000_000_000_000);
        assertEq(calculator.reservesEth(1), 49_990_000_000_000_000_000);
    }
}

contract TestOnChainDataBalancerGyroPoolCalculator is Test {
    TestBalancerCalculator private calculator;
    address internal constant GYRO_WSTETH_CBETH_POOL = 0xF7A826D47c8E02835D94fb0Aa40F0cC9505cb134;

    function getInitData(address poolAddress) internal pure returns (bytes memory) {
        return abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: poolAddress }));
    }

    function prepare() private {
        // System setup
        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));

        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));

        StatsCalculatorRegistry statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        StatsCalculatorFactory statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        // Calculator setup
        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;

        bytes memory initData = getInitData(GYRO_WSTETH_CBETH_POOL);
        calculator.initialize(depAprIds, initData);
    }

    function testBalancerGyroPoolCalculatorGetVirtualPrice() public {
        checkVirtualPrice(19_000_000, 246_998_202_499_216);
        checkVirtualPrice(19_700_000, 248_109_537_489_362);
    }

    function testBalancerGyroPoolCalculatorGetPoolTokens() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_000_000);

        prepare();

        (IERC20[] memory assets, uint256[] memory balances) = calculator.verifyGetPoolTokens();

        // Verify assets
        assertEq(assets.length, 2);
        assertEq(address(assets[0]), WSTETH_MAINNET);
        assertEq(address(assets[1]), CBETH_MAINNET);

        // Verify balances
        assertEq(balances.length, 2);
        assertEq(balances[0], 19_982_818_932_626_424_715);
        assertEq(balances[1], 1_911_148_030_461_858_601_740);
    }

    function checkVirtualPrice(uint256 targetBlock, uint256 expected) private {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), targetBlock);

        prepare();

        assertEq(calculator.verifyGetVirtualPrice(), expected);
    }
}

contract TestBalancerCalculator is BalancerGyroPoolCalculator {
    constructor(ISystemRegistry _systemRegistry, address vault) BalancerGyroPoolCalculator(_systemRegistry, vault) { }

    function verifyGetVirtualPrice() public view returns (uint256) {
        return getVirtualPrice();
    }

    function verifyGetPoolTokens() public view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return getPoolTokens();
    }
}
