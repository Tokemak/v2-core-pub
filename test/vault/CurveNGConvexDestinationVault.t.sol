// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable max-states-count
// solhint-disable max-line-length
// solhint-disable state-visibility
// solhint-disable const-name-snakecase
// solhint-disable avoid-low-level-calls
// solhint-disable const-name-snakecase

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { Errors } from "src/utils/Errors.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault, IDestinationVault } from "src/vault/DestinationVault.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { CurveNGConvexDestinationVault } from "src/vault/CurveNGConvexDestinationVault.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { MainRewarder } from "src/rewarders/MainRewarder.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";

import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import {
    CURVE_META_REGISTRY_MAINNET,
    WETH_MAINNET,
    OSETH_RETH_CURVE_NG_POOL,
    CONVEX_BOOSTER,
    BAL_VAULT,
    CVX_MAINNET,
    CRV_MAINNET,
    SWISE_MAINNET,
    RETH_MAINNET,
    RPL_MAINNET,
    OSETH_MAINNET
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

contract CurveNGConvexDestinationVaultTests is Test {
    address internal constant CONVEX_STAKING = 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e; // Curve osETH/ETH
    uint256 internal constant CONVEX_POOL_ID = 268;

    uint256 internal _mainnetFork;

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    DestinationVaultFactory internal _destinationVaultFactory;
    DestinationVaultRegistry internal _destinationVaultRegistry;
    DestinationRegistry internal _destinationTemplateRegistry;

    IAutopoolRegistry internal _autoPoolRegistry;
    IRootPriceOracle internal _rootPriceOracle;

    IWETH9 internal _asset;
    MainRewarder internal _rewarder;
    IERC20 internal _underlyer;

    TestIncentiveCalculator internal _testIncentiveCalculator;
    CurveResolverMainnet internal _curveResolver;
    CurveNGConvexDestinationVault internal _destVault;

    SwapRouter internal swapRouter;
    BalancerV2Swap internal balancerSwapper;

    address[] internal additionalTrackedTokens;

    address public constant zero = address(0);

    function setUp() public virtual {
        additionalTrackedTokens = new address[](0);

        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_841_102);
        vm.selectFork(_mainnetFork);

        vm.label(address(this), "testContract");

        _systemRegistry = new SystemRegistry(vm.addr(100), WETH_MAINNET);

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _asset = IWETH9(WETH_MAINNET);

        _systemRegistry.addRewardToken(WETH_MAINNET);

        _curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        _systemRegistry.setCurveResolver(address(_curveResolver));

        // Setup swap router

        _accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, address(this));

        swapRouter = new SwapRouter(_systemRegistry);
        _systemRegistry.setSwapRouter(address(swapRouter));

        balancerSwapper = new BalancerV2Swap(address(swapRouter), BAL_VAULT);
        // setup input for Balancer OSETH -> WETH
        ISwapRouter.SwapData[] memory osETHSwapRoute = new ISwapRouter.SwapData[](1);
        osETHSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: 0xDACf5Fa19b1f720111609043ac67A9818262850c,
            swapper: balancerSwapper,
            data: abi.encode(bytes32(0xdacf5fa19b1f720111609043ac67a9818262850c000000000000000000000635))
        });
        swapRouter.setSwapRoute(OSETH_MAINNET, osETHSwapRoute);

        // setup input for Balancer rETH -> WETH
        ISwapRouter.SwapData[] memory rETHSwapRoute = new ISwapRouter.SwapData[](1);
        rETHSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
            swapper: balancerSwapper,
            data: abi.encode(bytes32(0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112))
        });
        swapRouter.setSwapRoute(RETH_MAINNET, rETHSwapRoute);

        vm.label(address(swapRouter), "swapRouter");
        vm.label(address(balancerSwapper), "balancerSwapper");

        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));

        // Setup the Destination system
        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _destinationTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destinationTemplateRegistry));
        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));
        _destinationVaultFactory = new DestinationVaultFactory(_systemRegistry, 1, 1000);
        _destinationVaultRegistry.setVaultFactory(address(_destinationVaultFactory));

        _underlyer = IERC20(OSETH_RETH_CURVE_NG_POOL);
        vm.label(address(_underlyer), "underlyer");

        CurveNGConvexDestinationVault dvTemplate =
            new CurveNGConvexDestinationVault(_systemRegistry, CVX_MAINNET, CONVEX_BOOSTER);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: OSETH_RETH_CURVE_NG_POOL,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(OSETH_RETH_CURVE_NG_POOL));

        address payable newVault = payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt1"),
                initParamBytes
            )
        );
        vm.label(newVault, "destVault");

        _destVault = CurveNGConvexDestinationVault(newVault);

        _rootPriceOracle = IRootPriceOracle(vm.addr(34_399));
        vm.label(address(_rootPriceOracle), "rootPriceOracle");

        _mockSystemBound(address(_systemRegistry), address(_rootPriceOracle));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));
    }

    function _mockSystemBound(address registry, address addr) internal {
        vm.mockCall(addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(registry));
    }

    function _mockIsVault(address vault, bool isVault) internal {
        vm.mockCall(
            address(_autoPoolRegistry),
            abi.encodeWithSelector(IAutopoolRegistry.isVault.selector, vault),
            abi.encode(isVault)
        );
    }
}

contract StandardTests is CurveNGConvexDestinationVaultTests {
    function test_initializer_ConfiguresVault() public {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: OSETH_RETH_CURVE_NG_POOL,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);
        address payable newVault = payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );

        assertTrue(DestinationVault(newVault).underlyingTokens().length > 0);
    }

    function testExchangeName() public {
        assertEq(_destVault.exchangeName(), "curve");
    }

    function test_underlyingTotalSupply_ReturnsCorrectValue() public {
        assertEq(_destVault.underlyingTotalSupply(), 5_206_135_627_885_646_879_471);
    }

    function testUnderlyingTokens() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20(tokens[0]).symbol(), "osETH");
        assertEq(IERC20(tokens[1]).symbol(), "rETH");
    }

    function test_underlyingReserves() public {
        (address[] memory tokens, uint256[] memory reserves) = _destVault.underlyingReserves();
        assertEq(tokens.length, 2);
        assertEq(reserves.length, 2);

        assertEq(tokens[0], OSETH_MAINNET);
        assertEq(tokens[1], RETH_MAINNET);

        assertEq(reserves[0], 2_438_755_240_718_502_408_289);
        assertEq(reserves[1], 2_537_989_364_793_970_497_498);
    }

    function testDepositGoesToConvex() public {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 200e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        // Ensure the funds went to Convex
        assertEq(_destVault.externalQueriedBalance(), 100e18);
    }

    function testCollectRewards() public {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 200e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));

        IERC20 swise = IERC20(SWISE_MAINNET);
        IERC20 rpl = IERC20(RPL_MAINNET);
        IERC20 crv = IERC20(CRV_MAINNET);
        IERC20 cvx = IERC20(CVX_MAINNET);

        uint256 preBalSWISE = swise.balanceOf(address(this));
        uint256 preBalRPL = rpl.balanceOf(address(this));
        uint256 preBalCRV = crv.balanceOf(address(this));
        uint256 preBalCVX = cvx.balanceOf(address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 5, "len");
        assertEq(address(tokens[0]), SWISE_MAINNET, "t1");
        assertEq(address(tokens[1]), address(0), "t2");
        assertEq(address(tokens[2]), RPL_MAINNET, "t3");
        assertEq(address(tokens[3]), address(0), "t4");
        assertEq(address(tokens[3]), address(0), "t5");

        assertTrue(amounts[0] > 0);
        assertTrue(amounts[1] == 0);
        assertTrue(amounts[2] > 0);
        assertTrue(amounts[3] == 0);
        assertTrue(amounts[4] == 0);

        uint256 afterBalSWISE = swise.balanceOf(address(this));
        uint256 afterBalRPL = rpl.balanceOf(address(this));
        uint256 afterBalCRV = crv.balanceOf(address(this));
        uint256 afterBalCVX = cvx.balanceOf(address(this));

        assertEq(amounts[0], afterBalSWISE - preBalSWISE, "swise");
        assertEq(amounts[1], 0, "zero1");
        assertEq(amounts[2], afterBalRPL - preBalRPL);
        assertEq(amounts[3], afterBalCVX - preBalCVX);
        assertEq(amounts[3], 0);
        assertEq(amounts[4], afterBalCRV - preBalCRV);
        assertEq(amounts[4], 0);
    }

    function testWithdrawUnderlying() public {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 200e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        // Ensure the funds went to Convex
        assertEq(_destVault.externalQueriedBalance(), 100e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(50e18, receiver);

        assertEq(received, 50e18);
        assertEq(_underlyer.balanceOf(receiver), 50e18);
    }

    function testWithdrawBaseAsset() public {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 200e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        address receiver = makeAddr("receiver");
        uint256 startingBalance = _asset.balanceOf(receiver);

        (uint256 received,,) = _destVault.withdrawBaseAsset(50e18, receiver);

        assertEq(_asset.balanceOf(receiver) - startingBalance, 50.7654827053201272e18);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    //
    // Below tests test functionality introduced in response to Sherlock 625.
    // Link here: https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/invalid/625.md
    //
    function test_ExternalDebtBalance_UpdatesProperly_DepositAndWithdrawal() external {
        uint256 localDepositAmount = 1000;
        uint256 localWithdrawalAmount = 600;

        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), localDepositAmount);

        // Allow this address to deposit.
        _mockIsVault(address(this), true);

        // Check balances before deposit.
        assertEq(_destVault.externalDebtBalance(), 0);
        assertEq(_destVault.internalDebtBalance(), 0);

        // Approve and deposit.
        _underlyer.approve(address(_destVault), localDepositAmount);
        _destVault.depositUnderlying(localDepositAmount);

        // Check balances after deposit.
        assertEq(_destVault.internalDebtBalance(), 0);
        assertEq(_destVault.externalDebtBalance(), localDepositAmount);

        _destVault.withdrawUnderlying(localWithdrawalAmount, address(this));

        // Check balances after withdrawing underlyer.
        assertEq(_destVault.internalDebtBalance(), 0);
        assertEq(_destVault.externalDebtBalance(), localDepositAmount - localWithdrawalAmount);
    }

    function test_InternalDebtBalance_CannotBeManipulated() external {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        // Make sure balance of underlyer is on DV.
        assertEq(_underlyer.balanceOf(address(_destVault)), 1000);

        // Check to make sure `internalDebtBalance()` not changed. Used to be queried with `balanceOf(_destVault)`.
        assertEq(_destVault.internalDebtBalance(), 0);
    }

    function test_ExternalDebtBalance_CannotBeManipulated() external {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(_destVault), 1000);

        // Approve staking from dest vault address.
        vm.startPrank(address(_destVault));
        _underlyer.approve(CONVEX_BOOSTER, 1000);

        // Low level call, no need for interface for test.
        (, bytes memory payload) =
            CONVEX_BOOSTER.call(abi.encodeWithSignature("deposit(uint256,uint256,bool)", CONVEX_POOL_ID, 1000, true));
        vm.stopPrank();

        // Check that booster deposit returns true.
        assertEq(abi.decode(payload, (bool)), true);

        // Use low level call to check balance on Convex staking contract.
        (, payload) = CONVEX_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Make sure that DV not picking up external balances.
        assertEq(_destVault.externalDebtBalance(), 0);
    }

    function test_InternalQueriedBalance_CapturesUnderlyerInVault() external {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        assertEq(_destVault.internalQueriedBalance(), 1000);
    }

    function test_ExternalQueriedBalance_CapturesUnderlyerNotStakedByVault() external {
        // Get some tokens to play with
        deal(OSETH_RETH_CURVE_NG_POOL, address(_destVault), 1000);

        // Approve staking from dest vault address.
        vm.startPrank(address(_destVault));
        _underlyer.approve(CONVEX_BOOSTER, 1000);

        // Low level call, no need for interface for test.
        (, bytes memory payload) =
            CONVEX_BOOSTER.call(abi.encodeWithSignature("deposit(uint256,uint256,bool)", CONVEX_POOL_ID, 1000, true));
        vm.stopPrank();

        // Check that booster deposit returns true.
        assertEq(abi.decode(payload, (bool)), true);

        // Use low level call to check balance on Convex staking contract.
        (, payload) = CONVEX_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Make sure that DV not picking up external balances.
        assertEq(_destVault.externalQueriedBalance(), 1000);
    }

    function test_DestinationVault_getPool() external {
        assertEq(IDestinationVault(_destVault).getPool(), OSETH_RETH_CURVE_NG_POOL);
    }
}

contract ValidateCalculator is CurveNGConvexDestinationVaultTests {
    TestIncentiveCalculator private _testIncentiveCalculatorLocal;

    function test_validateCalculator_EnsuresMatchingUnderlyingWithCalculator() external {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: OSETH_RETH_CURVE_NG_POOL,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculatorLocal = new TestIncentiveCalculator();
        _testIncentiveCalculatorLocal.setLpToken(address(_underlyer));
        _testIncentiveCalculatorLocal.setPoolAddress(address(OSETH_RETH_CURVE_NG_POOL));

        TestERC20 badUnderlyer = new TestERC20("X", "X");

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, address(_underlyer), address(badUnderlyer), "lp"
            )
        );
        payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(badUnderlyer),
                address(_testIncentiveCalculatorLocal),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );
    }

    function test_validateCalculator_EnsuresMatchingPoolWithCalculator() external {
        address badPool = makeAddr("badPool");

        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: badPool,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculatorLocal = new TestIncentiveCalculator();
        _testIncentiveCalculatorLocal.setLpToken(address(_underlyer));
        _testIncentiveCalculatorLocal.setPoolAddress(address(OSETH_RETH_CURVE_NG_POOL));

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector,
                address(OSETH_RETH_CURVE_NG_POOL),
                address(badPool),
                "pool"
            )
        );
        payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculatorLocal),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );
    }
}

contract Constructor is CurveNGConvexDestinationVaultTests {
    function test_RevertIf_ConvexBoosterIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_convexBooster"));
        new CurveNGConvexDestinationVault(_systemRegistry, CVX_MAINNET, zero);
    }
}

contract Initialize is CurveNGConvexDestinationVaultTests {
    using Clones for address;

    CurveNGConvexDestinationVault internal vault;
    TestIncentiveCalculator internal _testIncentiveCalculatorLocal;
    bytes internal defaultInitParamBytes;

    function setUp() public override {
        super.setUp();

        address vaultTemplate = address(new CurveNGConvexDestinationVault(_systemRegistry, CVX_MAINNET, CONVEX_BOOSTER));

        _rewarder = MainRewarder(makeAddr("REWARDER"));
        CurveConvexDestinationVault.InitParams memory defaultInitParams = CurveConvexDestinationVault.InitParams({
            curvePool: OSETH_RETH_CURVE_NG_POOL,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });

        defaultInitParamBytes = abi.encode(defaultInitParams);

        vault = CurveNGConvexDestinationVault(payable(vaultTemplate.cloneDeterministic(bytes32(block.number))));

        _testIncentiveCalculatorLocal = new TestIncentiveCalculator();
        _testIncentiveCalculatorLocal.setLpToken(address(_underlyer));
        _testIncentiveCalculatorLocal.setPoolAddress(OSETH_RETH_CURVE_NG_POOL);
    }

    function test_RevertIf_ParamConvexStakingIsZeroAddress() public {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: OSETH_RETH_CURVE_NG_POOL,
            convexStaking: zero,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "convexStaking"));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            initParamBytes
        );
    }

    function test_RevertIf_ParamCurvePoolIsZeroAddress() public {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: zero,
            convexStaking: CONVEX_STAKING,
            convexPoolId: CONVEX_POOL_ID
        });
        bytes memory initParamBytes = abi.encode(initParams);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "curvePool"));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            initParamBytes
        );
    }

    function test_RevertIf_PoolIsShutdown() public {
        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector),
            abi.encode(OSETH_RETH_CURVE_NG_POOL, zero, zero, CONVEX_STAKING, zero, true)
        );
        vm.expectRevert(abi.encodeWithSelector(CurveConvexDestinationVault.PoolShutdown.selector));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            defaultInitParamBytes
        );
    }

    function test_RevertIf_LpTokenFromBoosterIsZeroAddress() public {
        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector),
            abi.encode(zero, zero, zero, zero, zero, false)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lpToken"));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            defaultInitParamBytes
        );
    }

    function test_RevertIf_LpTokenIsDifferentThanTheOneFromBooster() public {
        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector),
            abi.encode(address(1), zero, zero, zero, zero, false)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "lpToken"));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            defaultInitParamBytes
        );
    }

    function test_RevertIf_CrvRewardsIsDifferentThanTheOneFromBooster() public {
        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector),
            abi.encode(OSETH_RETH_CURVE_NG_POOL, zero, zero, zero, zero, false)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "crvRewards"));

        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            defaultInitParamBytes
        );
    }

    function test_RevertIf_NumTokensIsZero() public {
        address[8] memory tokens;
        vm.mockCall(
            address(_curveResolver),
            abi.encodeWithSelector(ICurveResolver.resolveWithLpToken.selector),
            abi.encode(tokens, 0, address(1), false)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "numTokens"));
        vault.initialize(
            IERC20(address(_asset)),
            _underlyer,
            _rewarder,
            address(_testIncentiveCalculatorLocal),
            additionalTrackedTokens,
            defaultInitParamBytes
        );
    }
}

contract PoolType is CurveNGConvexDestinationVaultTests {
    function test_handleCurveNG() public {
        assertEq(_destVault.poolType(), "curveNG");
    }
}
