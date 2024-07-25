// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import {
    WETH9_BASE,
    WSTETH_BASE,
    AERODROME_SWAP_ROUTER_BASE,
    WSTETH_WETH_AERO_BASE,
    WSTETH_WETH_AERO_BASE_GAUGE,
    AERO_BASE,
    AERODROME_VOTER_BASE
} from "test/utils/Addresses.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController, IAccessController } from "src/security/AccessController.sol";
import { SwapRouter, ISwapRouter } from "src/swapper/SwapRouter.sol";
import { AerodromeSwap } from "src/swapper/adapters/AerodromeSwap.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { AerodromeDestinationVault, DestinationVault } from "src/vault/AerodromeDestinationVault.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { IRouter } from "src/interfaces/external/aerodrome/IRouter.sol";
import { IPool } from "src/interfaces/external/aerodrome/IPool.sol";
import { IAerodromeGauge } from "src/interfaces/external/aerodrome/IAerodromeGauge.sol";
import { Errors } from "src/utils/Errors.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";

// solhint-disable func-name-mixedcase,max-states-count,const-name-snakecase

contract AerodromeDestinationVaultBaseTest is Test {
    SystemRegistry public _systemRegistry;
    IAccessController public _accessController;
    ISwapRouter public _swapRouter;
    AerodromeSwap public _aeroSwap;
    DestinationVaultRegistry public _destVaultRegistry;
    DestinationRegistry public _destTempRegistry;
    DestinationVaultFactory public _dvFactory;
    TestIncentiveCalculator public _testIncentiveCalculator;
    AerodromeDestinationVaultWrapper public _dv;
    IRootPriceOracle public _oracle;
    IAutopoolRegistry public _autopoolRegistry;
    IPool public _aeroPool;
    IAerodromeGauge public _aeroGauge;

    IERC20 public _underlyer;

    IWETH9 public _asset;

    address[] public additionalTrackedTokens;

    event UnderlyingDeposited(uint256 amount, address sender);
    event UnderlyingWithdraw(uint256 amount, address sender, address to);
    event UnderlyerRecovered(address destination, uint256 totalAmount);
    event BaseAssetWithdraw(uint256 shares, address account, address to);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 15_674_952);

        _aeroPool = IPool(WSTETH_WETH_AERO_BASE);
        _aeroGauge = IAerodromeGauge(WSTETH_WETH_AERO_BASE_GAUGE);

        _systemRegistry = new SystemRegistry(makeAddr("TOKE"), WETH9_BASE);

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _asset = IWETH9(WETH9_BASE);
        _systemRegistry.addRewardToken(WETH9_BASE);

        // Swap router setup
        _swapRouter = new SwapRouter(_systemRegistry);
        _aeroSwap = new AerodromeSwap(address(AERODROME_SWAP_ROUTER_BASE), address(_swapRouter));

        // Aerodrome routing
        IRouter.Route[] memory aeroRoute = new IRouter.Route[](1);
        aeroRoute[0] = IRouter.Route({
            from: WSTETH_BASE,
            to: WETH9_BASE,
            stable: false,
            factory: IRouter(AERODROME_SWAP_ROUTER_BASE).defaultFactory()
        });
        ISwapRouter.SwapData[] memory route = new ISwapRouter.SwapData[](1);
        route[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: AERODROME_SWAP_ROUTER_BASE,
            swapper: _aeroSwap,
            data: abi.encode(aeroRoute)
        });
        _swapRouter.setSwapRoute(WSTETH_BASE, route);
        _systemRegistry.setSwapRouter(address(_swapRouter));

        // Set up destination system
        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));

        _destVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _destTempRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destTempRegistry));
        _systemRegistry.setDestinationVaultRegistry(address(_destVaultRegistry));
        _dvFactory = new DestinationVaultFactory(_systemRegistry, 1, 1000);
        _destVaultRegistry.setVaultFactory(address(_dvFactory));

        _underlyer = IERC20(WSTETH_WETH_AERO_BASE);

        AerodromeDestinationVaultWrapper dvTemplate =
            new AerodromeDestinationVaultWrapper(_systemRegistry, AERODROME_SWAP_ROUTER_BASE, AERODROME_VOTER_BASE);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destTempRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destTempRegistry.register(dvTypes, dvAddresses);

        AerodromeDestinationVault.InitParams memory initParams =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: WSTETH_WETH_AERO_BASE_GAUGE });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));

        additionalTrackedTokens = new address[](0);

        address newVault = _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt1"),
            initParamBytes
        );

        _dv = AerodromeDestinationVaultWrapper(newVault);

        // Oracle
        _oracle = IRootPriceOracle(makeAddr("ORACLE"));
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(_systemRegistry)
        );

        // Autopool
        _autopoolRegistry = IAutopoolRegistry(makeAddr("AUTOPOOL_REGISTRY"));
        vm.mockCall(
            address(_autopoolRegistry),
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(_systemRegistry)
        );
        _systemRegistry.setAutopoolRegistry(address(_autopoolRegistry));
    }

    function _mockIsVault() internal {
        vm.mockCall(
            address(_autopoolRegistry),
            abi.encodeWithSelector(IAutopoolRegistry.isVault.selector, address(this)),
            abi.encode(true)
        );
    }

    function _approveUnderlyer(address spender) internal {
        _underlyer.approve(spender, type(uint256).max);
    }

    function _dealLP(address dealTo) internal {
        deal(WSTETH_WETH_AERO_BASE, dealTo, 1e18);
    }

    function _runDVDeposit(uint256 amount) internal {
        _dealLP(address(this));
        _mockIsVault();
        _approveUnderlyer(address(_dv));
        _dv.depositUnderlying(amount);
    }
}

contract AerodromeDVViewFunctions is AerodromeDestinationVaultBaseTest {
    function test_internalDebtBalance_ReturnsZero() public {
        assertEq(_dv.internalDebtBalance(), 0);
    }

    function test_externalDebtBalance_ReturnsSupply() public {
        assertEq(_dv.externalDebtBalance(), _dv.totalSupply());
    }

    function test_externalQueriedBalance_ReturnsSameAsGaugeBalance() public {
        _mockIsVault();
        _dealLP((address(this)));
        _approveUnderlyer(address(_dv));
        _dv.depositUnderlying(1e18);

        assertEq(_dv.externalQueriedBalance(), _aeroGauge.balanceOf(address(_dv)));
    }

    function test_exchangeName() public {
        assertEq(_dv.exchangeName(), "aerodrome");
    }

    function test_poolType() public {
        assertEq(_dv.poolType(), "vAMM");
    }

    function test_poolDealInEth() public {
        assertEq(_dv.poolDealInEth(), false);
    }

    function test_underlyingTokens() public {
        address[] memory tokens = _dv.underlyingTokens();
        assertEq(tokens[0], _aeroPool.token0());
        assertEq(tokens[1], _aeroPool.token1());
    }

    function test_getPool() public {
        assertEq(_dv.getPool(), address(_underlyer));
    }
}

contract Constructor is AerodromeDestinationVaultBaseTest {
    function test_RevertIf_RouterZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_aerodromeRouter"));
        new AerodromeDestinationVault(_systemRegistry, address(0), AERODROME_VOTER_BASE);
    }

    function test_RevertIf_VoterZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_aerodromeVoter"));
        new AerodromeDestinationVault(_systemRegistry, AERODROME_SWAP_ROUTER_BASE, address(0));
    }

    function test_StateSet() public {
        assertEq(_dv.aerodromeRouter(), AERODROME_SWAP_ROUTER_BASE);
        assertEq(address(_dv.aerodromeVoter()), AERODROME_VOTER_BASE);
    }
}

contract Initialize is AerodromeDestinationVaultBaseTest {
    function test_StateSetDuringInit() public {
        address[] memory underlyingTokens = _dv.underlyingTokens();

        assertEq(_dv.aerodromeGauge(), WSTETH_WETH_AERO_BASE_GAUGE);
        assertEq(_dv.aerodromeRouter(), AERODROME_SWAP_ROUTER_BASE);
        assertEq(_dv.isStable(), false);
        assertEq(underlyingTokens[0], _aeroPool.token0());
        assertEq(underlyingTokens[1], _aeroPool.token1());
    }

    function test_RevertIf_GaugeZero() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: address(0) });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "localGauge"));
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }

    function test_RevertIf_VoterGauge_AndLocalGuage_DoNotMatch() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: address(_aeroGauge) });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        address fakeGauge = makeAddr("FAKE_GAUGE");
        vm.mockCall(
            AERODROME_VOTER_BASE,
            abi.encodeWithSelector(IVoter.gauges.selector, address(_aeroPool)),
            abi.encode(fakeGauge)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "localGauge"));
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }

    function test_RevertIf_GaugeNotAlive() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: address(_aeroGauge) });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        vm.mockCall(
            AERODROME_VOTER_BASE,
            abi.encodeWithSelector(IVoter.isAlive.selector, address(_aeroGauge)),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IVoter.GaugeNotAlive.selector, address(_aeroGauge)));
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }

    function test_RevertIf_LPOnCalc_AndUnderlying_DoNotMatch() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: WSTETH_WETH_AERO_BASE_GAUGE });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        address fakeLP = makeAddr("NOT_LP");
        vm.mockCall(
            address(_testIncentiveCalculator),
            abi.encodeWithSelector(TestIncentiveCalculator.lpToken.selector),
            abi.encode(fakeLP)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, fakeLP, address(_underlyer), "lp"
            )
        );
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }

    function test_RevertIf_PoolOnCalc_AndUnderlying_DoNotMatch() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: WSTETH_WETH_AERO_BASE_GAUGE });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        address fakePool = makeAddr("NOT_POOL");
        vm.mockCall(
            address(_testIncentiveCalculator),
            abi.encodeWithSelector(TestIncentiveCalculator.pool.selector),
            abi.encode(fakePool)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, fakePool, address(_underlyer), "pool"
            )
        );
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }

    function test_RevertIf_UnderlyerAndStakedDoNotMatch() public {
        AerodromeDestinationVault.InitParams memory params =
            AerodromeDestinationVault.InitParams({ aerodromeGauge: WSTETH_WETH_AERO_BASE_GAUGE });

        _accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        address fakeStakingToken = makeAddr("FAKE_STAKING");
        vm.mockCall(
            address(_aeroGauge),
            abi.encodeWithSelector(IAerodromeGauge.stakingToken.selector),
            abi.encode(fakeStakingToken)
        );

        vm.expectRevert(Errors.InvalidConfiguration.selector);
        _dvFactory.create(
            "template",
            address(_asset),
            address(_underlyer),
            address(_testIncentiveCalculator),
            additionalTrackedTokens,
            keccak256("salt"),
            abi.encode(params)
        );
    }
}

contract AerodromeOnDeposit is AerodromeDestinationVaultBaseTest {
    function test_onDeposit_Isolated() public {
        // Deal to DV, tokens transferred from there
        _dealLP(address(_dv));

        // Mints to DV
        uint256 balanceBefore = _aeroGauge.balanceOf(address(_dv));
        _dv.onDeposit(1e18);
        uint256 balanceAfter = _aeroGauge.balanceOf(address(_dv));

        // gauge mints 1:1
        assertEq(balanceAfter - balanceBefore, 1e18);
    }

    function test_onDeposit_Through_depositUnderlyer() public {
        _dealLP(address(this));
        _approveUnderlyer(address(_dv));
        _mockIsVault();

        uint256 dvTokenBalanceBefore = _dv.balanceOf(address(this));
        uint256 gaugeUnderlyerBalanceBefore = _underlyer.balanceOf(address(_aeroGauge));
        uint256 gaugeBalanceDVBefore = _aeroGauge.balanceOf(address(_dv));

        vm.expectEmit(true, true, true, true);
        emit UnderlyingDeposited(1e18, address(this));
        _dv.depositUnderlying(1e18);

        uint256 dvTokenBalanceAfter = _dv.balanceOf(address(this));
        uint256 gaugeUnderlyerBalanceAfter = _underlyer.balanceOf(address(_aeroGauge));
        uint256 gaugeBalanceDVAfter = _aeroGauge.balanceOf(address(_dv));

        // DV mints 1:1
        assertEq(dvTokenBalanceAfter - dvTokenBalanceBefore, 1e18);
        assertEq(gaugeUnderlyerBalanceAfter - gaugeUnderlyerBalanceBefore, 1e18);

        // Gauge mints 1:1
        assertEq(gaugeBalanceDVAfter - gaugeBalanceDVBefore, 1e18);
    }
}

contract AerodromeEnsureLocalUnderlyingBalance is AerodromeDestinationVaultBaseTest {
    function setUp() public virtual override {
        super.setUp();

        _runDVDeposit(1e18);
    }

    function test_ensureLocalUnderlyingBalance_Isolated() public {
        uint256 underlyerBalanceInDVBefore = _underlyer.balanceOf(address(_dv));
        uint256 gaugeBalanceDVBefore = _aeroGauge.balanceOf(address(_dv));

        assertGt(gaugeBalanceDVBefore, 0);

        _dv.ensureLocalUnderlyingBalance(1e18);

        uint256 underlyerBalanceInDVAfter = _underlyer.balanceOf(address(_dv));
        uint256 gaugeBalanceDVAfter = _aeroGauge.balanceOf(address(_dv));

        assertEq(underlyerBalanceInDVAfter - underlyerBalanceInDVBefore, 1e18);
        assertEq(gaugeBalanceDVAfter, 0);
    }

    function test_ensureLocalUnderlyingBalance_Through_withdrawUnderlying() public {
        uint256 dvSharesAddressThisBefore = _dv.balanceOf(address(this)); // 1e18
        uint256 underlyerBalanceAddressThisBefore = _underlyer.balanceOf(address(this)); // 0
        uint256 underlyerGaugeBalanceBefore = _underlyer.balanceOf(address(_aeroGauge)); // 1e18
        uint256 dvGaugeBalanceBefore = _aeroGauge.balanceOf(address(_dv)); // 1e18

        assertEq(dvSharesAddressThisBefore, 1e18);
        assertEq(underlyerBalanceAddressThisBefore, 0);
        assertGe(underlyerGaugeBalanceBefore, 1e18);
        assertEq(dvGaugeBalanceBefore, 1e18);

        vm.expectEmit(true, true, true, true);
        emit UnderlyingWithdraw(1e18, address(this), address(this));
        _dv.withdrawUnderlying(1e18, address(this));

        uint256 dvSharesAddressThisAfter = _dv.balanceOf(address(this)); // 0
        uint256 underlyerBalanceAddressThisAfter = _underlyer.balanceOf(address(this)); // 1e18
        uint256 underlyerGaugeBalanceAfter = _underlyer.balanceOf(address(_aeroGauge));
        uint256 dvGaugeBalanceAfter = _aeroGauge.balanceOf(address(_dv)); // 0

        assertEq(dvSharesAddressThisAfter, 0);
        assertEq(underlyerBalanceAddressThisAfter, 1e18);
        assertEq(underlyerGaugeBalanceBefore - underlyerGaugeBalanceAfter, 1e18);
        assertEq(dvGaugeBalanceAfter, 0);
    }

    function test_ensureLocalUnderlyingBalance_Through_recoverUnderlying() public {
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

        // Stake some to Aerodrome gauge on behalf of dv to get extra queried balance.
        _dealLP(address(this));
        _approveUnderlyer(address(_aeroGauge));
        _aeroGauge.deposit(1e18, address(_dv));

        assertGt(_dv.externalQueriedBalance(), _dv.externalDebtBalance());

        uint256 dvBalanceGaugeBefore = _aeroGauge.balanceOf(address(_dv));
        uint256 destinationUnderlyerBalanceBefore = _underlyer.balanceOf(address(this));

        assertEq(dvBalanceGaugeBefore, 2e18);
        assertEq(destinationUnderlyerBalanceBefore, 0);

        vm.expectEmit(true, true, true, true);
        emit UnderlyerRecovered(address(this), 1e18);
        _dv.recoverUnderlying(address(this));

        uint256 dvBalanceGaugeAfter = _aeroGauge.balanceOf(address(_dv));
        uint256 destinationUnderlyerBalanceAfter = _underlyer.balanceOf(address(this));

        assertEq(_dv.externalQueriedBalance(), _dv.externalDebtBalance());
        assertEq(dvBalanceGaugeAfter, 1e18);
        assertEq(destinationUnderlyerBalanceAfter, 1e18);
    }
}

contract AerodromeCollectRewards is AerodromeDestinationVaultBaseTest {
    IERC20 public constant rewardToken = IERC20(AERO_BASE);

    function setUp() public virtual override {
        super.setUp();

        _runDVDeposit(1e18);
    }

    function test_collectRewards_Aerodrome() public {
        _accessController.setupRole(Roles.LIQUIDATOR_MANAGER, address(this));
        uint256 aeroTokenBalanceBefore = rewardToken.balanceOf(address(this));

        assertEq(aeroTokenBalanceBefore, 0);
        assertEq(_aeroGauge.earned(address(_dv)), 0);

        // Warp timestamp to get rewards
        vm.warp(block.timestamp + 52 weeks);

        uint256 earnedAfterWarp = _aeroGauge.earned(address(_dv));
        assertGt(earnedAfterWarp, 0);

        (uint256[] memory amounts, address[] memory tokens) = _dv.collectRewards();

        uint256 aeroTokenBalanceAfter = rewardToken.balanceOf(address(this));

        assertEq(amounts[0], earnedAfterWarp);
        assertEq(tokens[0], address(rewardToken));
        assertEq(aeroTokenBalanceAfter, earnedAfterWarp);
    }
}

contract AerodromeBurnUnderlyer is AerodromeDestinationVaultBaseTest {
    function test_burnUnderlyer_Isolated() external {
        _dealLP(address(this));
        _aeroPool.transfer(address(_dv), 1e18);

        address[] memory tokens = _dv.underlyingTokens();
        IERC20 token0 = IERC20(tokens[0]);
        IERC20 token1 = IERC20(tokens[1]);

        uint256 balanceToken0Before = token0.balanceOf(address(_dv));
        uint256 balanceToken1Before = token1.balanceOf(address(_dv));

        assertEq(balanceToken0Before, 0);
        assertEq(balanceToken1Before, 0);

        address[] memory tokensFromBurn = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        (tokensFromBurn, amounts) = _dv.burnUnderlyer(1e18);

        uint256 balanceToken0After = token0.balanceOf(address(_dv));
        uint256 balanceToken1After = token1.balanceOf(address(_dv));

        assertEq(tokensFromBurn[0], address(token0));
        assertEq(tokensFromBurn[1], address(token1));
        assertGt(balanceToken0After, 0);
        assertGt(balanceToken1After, 0);
        assertEq(balanceToken0After, amounts[0]);
        assertEq(balanceToken1After, amounts[1]);
        assertEq(_aeroPool.balanceOf(address(_dv)), 0);
    }
}

/// @title `DestinationVault.withdrawBaseAsset()` touches both `_ensureUnderlying` and `_burnUnderlyer`
contract AerodromeWithdrawBaseAsset is AerodromeDestinationVaultBaseTest {
    function test_ensureLocalUnderlyingBalance_And_burnUnderlyer_Through_withdrawBaseAsset() public {
        _runDVDeposit(1e18);

        uint256 baseAmountBefore = _asset.balanceOf(address(this));
        uint256 dvTokenAmountBefore = _dv.balanceOf(address(this));
        uint256 dvGaugeAmountBefore = _aeroGauge.balanceOf(address(_dv));
        uint256 poolTotalSupplyBefore = _aeroPool.totalSupply();

        assertEq(baseAmountBefore, 0);
        assertEq(dvTokenAmountBefore, 1e18);
        assertEq(dvGaugeAmountBefore, 1e18);

        vm.expectEmit(true, true, true, true);
        emit BaseAssetWithdraw(1e18, address(this), address(this));
        _dv.withdrawBaseAsset(1e18, address(this));

        uint256 baseAmountAfter = _asset.balanceOf(address(this));
        uint256 dvTokenAmountAfter = _dv.balanceOf(address(this));
        uint256 dvGaugeAmountAfter = _aeroGauge.balanceOf(address(_dv));
        uint256 poolTotalSupplyAfter = _aeroPool.totalSupply();

        assertGt(baseAmountAfter, 0);
        assertEq(dvTokenAmountAfter, 0);
        assertEq(dvGaugeAmountAfter, 0);
        assertEq(poolTotalSupplyAfter, poolTotalSupplyBefore - 1e18);
    }
}

/// @title Expose external interactions for direct testing.
/// @dev '_collectRewards()' is exposed directly via `collecRewards()` in DestinationVault.sol
contract AerodromeDestinationVaultWrapper is AerodromeDestinationVault {
    constructor(
        ISystemRegistry _systemRegistry,
        address aerodromeRouter,
        address aerodromeVoter
    ) AerodromeDestinationVault(_systemRegistry, aerodromeRouter, aerodromeVoter) { }

    function onDeposit(uint256 amount) public {
        _onDeposit(amount);
    }

    function ensureLocalUnderlyingBalance(uint256 amount) public {
        _ensureLocalUnderlyingBalance(amount);
    }

    function burnUnderlyer(uint256 amount) public returns (address[] memory tokens, uint256[] memory amounts) {
        (tokens, amounts) = _burnUnderlyer(amount);
    }
}
