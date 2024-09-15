// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable avoid-low-level-calls,gas-custom-errors,max-line-length
// solhint-disable func-name-mixedcase,contract-name-camelcase,max-states-count,avoid-low-level-calls,gas-custom-errors

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { STETH_MAINNET, TOKE_MAINNET, WETH_MAINNET, WSTETH_MAINNET, CURVE_ETH } from "test/utils/Addresses.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurityL1 } from "src/security/SystemSecurityL1.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";
import { AutopoolETHStrategyConfig } from "src/strategy/AutopoolETHStrategyConfig.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { WstETHEthOracle } from "src/oracles/providers/WstETHEthOracle.sol";
import { ChainlinkOracle } from "src/oracles/providers/ChainlinkOracle.sol";
import { EthPeggedOracle } from "src/oracles/providers/EthPeggedOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { TokenReturnSolver } from "test/mocks/TokenReturnSolver.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";

abstract contract AutopoolTests is Test {
    address internal constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address internal constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    function _setUp(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
    }
}

contract RedeemTests is AutopoolTests {
    SystemRegistry internal _systemRegistry;

    function setUp() public virtual {
        _setUp(19_386_214);

        vm.startPrank(V2_DEPLOYER);

        _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);

        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, V2_DEPLOYER);

        SwapRouter swapRouter = new SwapRouter(_systemRegistry);
        _systemRegistry.setSwapRouter(address(swapRouter));

        CurveV1StableSwap curveV1Swap = new CurveV1StableSwap(address(swapRouter), address(_systemRegistry.weth()));

        // route STETH_MAINNET -> ETH
        ISwapRouter.SwapData[] memory stEthToEthRoute = new ISwapRouter.SwapData[](1);
        stEthToEthRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            swapper: curveV1Swap,
            data: abi.encode(1, 0) // SellIndex, BuyIndex
         });
        swapRouter.setSwapRoute(STETH_MAINNET, stEthToEthRoute);

        vm.stopPrank();
    }

    function test_Redeem() public {
        vm.startPrank(V2_DEPLOYER);

        AutopoolETH pool = AutopoolETH(0x21eB47113E148839c30E1A9CA2b00Ea1317b50ed);
        IWETH9 weth = IWETH9(pool.asset());
        uint256 startingBalance = weth.balanceOf(V2_DEPLOYER);
        assertEq(startingBalance, 0.699e18, "startingBalance");

        address sharesHolder = 0x804986F81826034F7753484B936A634c706f1aDF;
        uint256 sharesToBurn = pool.balanceOf(sharesHolder);

        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        accessController.grantRole(Roles.AUTO_POOL_REPORTING_EXECUTOR, V2_DEPLOYER);

        uint256 assets = pool.redeem(sharesToBurn, V2_DEPLOYER, sharesHolder);

        assertEq(assets, 15.479430294412169634e18, "receivedAssets");

        vm.stopPrank();
    }
}

contract ShutdownDestination is AutopoolTests {
    AutopoolETH internal _pool;
    SystemRegistry internal _systemRegistry;

    function setUp() public {
        _setUp(19_640_105);
        _pool = AutopoolETH(0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6);
        _systemRegistry = SystemRegistry(address(_pool.getSystemRegistry()));
    }

    function test_DestinationShutdownReleasesAssetsAndCanRemove() public {
        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        // stETH/ETH-ng
        DestinationVault destinationToShutdown = DestinationVault(0xba1a495630a948f0942081924a5682f4f55E3e82);
        IWETH9 baseAsset = _systemRegistry.weth();

        TokenReturnSolver solver = new TokenReturnSolver(vm);

        // Shutdown Vault
        vm.startPrank(V2_DEPLOYER);
        destinationToShutdown.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        accessController.grantRole(Roles.SOLVER, address(this));
        vm.stopPrank();

        uint256 amountWethFromRebalance = 26.35e18;

        bytes memory data = solver.buildForIdleIn(_pool, amountWethFromRebalance);

        uint256 previousBalance = baseAsset.balanceOf(address(_pool));
        uint256 previousIdle = _pool.getAssetBreakdown().totalIdle;

        _pool.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationOut: address(destinationToShutdown),
                tokenOut: address(destinationToShutdown.underlying()),
                amountOut: 25.692933029349164507e18,
                destinationIn: address(_pool),
                tokenIn: _pool.asset(),
                amountIn: amountWethFromRebalance
            }),
            data
        );

        assertEq(baseAsset.balanceOf(address(_pool)), previousBalance + amountWethFromRebalance, "bal");
        assertEq(_pool.getAssetBreakdown().totalIdle, previousIdle + amountWethFromRebalance, "idle");

        vm.startPrank(V2_DEPLOYER);
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(destinationToShutdown);
        _pool.removeDestinations(toRemove);
        vm.stopPrank();
    }
}

abstract contract AutopoolFullDeployTests is Test {
    uint256 internal _defaultRewardRatioDest = 800;
    uint256 internal _defaultRewardBlockDurationDest = 100;
    uint256 internal _saltIx;

    address internal deployer = makeAddr("deployer");

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    SystemSecurityL1 internal _systemSecurity;
    AutopoolRegistry internal _autoPoolRegistry;
    DestinationRegistry internal _destinationTemplateRegistry;
    DestinationVaultRegistry internal _destinationVaultRegistry;
    DestinationVaultFactory internal _destinationVaultFactory;
    SwapRouter internal _swapRouter;
    RootPriceOracle internal _rootPriceOracle;
    AccToke internal _accToke;
    CurveResolverMainnet internal _curveResolver;
    AutopoolFactory internal _autopoolFactory;
    IWETH9 internal _weth;

    // Destination Vaults
    DestinationVault internal _curveStEthNgDv;

    // Autopool
    AutopoolETH internal _pool;
    FundedSolver internal _solver;

    function _setUp(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), blockNumber);

        _weth = IWETH9(WETH_MAINNET);

        // System Registry
        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _systemRegistry.addRewardToken(TOKE_MAINNET);
        _systemRegistry.addRewardToken(WETH_MAINNET);

        // Access Controller
        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        // System Security
        _systemSecurity = new SystemSecurityL1(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        // Autopool Registry
        _autoPoolRegistry = new AutopoolRegistry(_systemRegistry);
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        // Destination Template Registry
        _destinationTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destinationTemplateRegistry));

        // Destination Vault Registry
        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));

        // Destination Vault Factory
        _destinationVaultFactory =
            new DestinationVaultFactory(_systemRegistry, _defaultRewardRatioDest, _defaultRewardBlockDurationDest);
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        _destinationVaultRegistry.setVaultFactory(address(_destinationVaultFactory));

        // Swap Router
        _swapRouter = new SwapRouter(_systemRegistry);
        _systemRegistry.setSwapRouter(address(_swapRouter));

        // Root Price Oracle
        _rootPriceOracle = new RootPriceOracle(_systemRegistry);
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        // AccToke setup.
        _accToke = new AccToke(_systemRegistry, block.timestamp, 30 days);
        _systemRegistry.setAccToke(address(_accToke));

        // Curve Resolver
        _curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC));
        _systemRegistry.setCurveResolver(address(_curveResolver));

        // Setup Destinations
        _setupCurveConvexDestinationTemplate();
        _curveStEthNgDv = _deployStEthEthNgSetupData();
        _setupSwapRoutes();

        // Setup Oracles
        _setupOracles(_systemRegistry);

        // Setup Autopool
        _setupAutopool();

        _solver = new FundedSolver();
        _accessController.grantRole(Roles.SOLVER, address(this));

        address[] memory destinations = new address[](1);
        destinations[0] = address(_curveStEthNgDv);
        _accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, address(this));
        _pool.addDestinations(destinations);
    }

    function test_SetUp() public {
        assertNotEq(address(_pool), address(0), "pool");
    }

    function _setupSwapRoutes() internal {
        CurveV1StableSwap curveSwapper = new CurveV1StableSwap(address(_swapRouter), address(_systemRegistry.weth()));
        // setup input for Curve STETH -> WETH
        int128 sellIndex = 1;
        int128 buyIndex = 0;
        ISwapRouter.SwapData[] memory stethSwapRoute = new ISwapRouter.SwapData[](1);
        stethSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            swapper: curveSwapper,
            data: abi.encode(sellIndex, buyIndex)
        });

        _accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, address(this));
        _swapRouter.setSwapRoute(STETH_MAINNET, stethSwapRoute);
    }

    function _setupOracles(SystemRegistry systemRegistry) internal {
        _accessController.grantRole(Roles.ORACLE_MANAGER, address(this));

        ChainlinkOracle chainlinkOracle = new ChainlinkOracle(_systemRegistry);

        CurveV1StableEthOracle curveV1Oracle =
            new CurveV1StableEthOracle(systemRegistry, systemRegistry.curveResolver());

        _registerBaseTokens(_rootPriceOracle, chainlinkOracle);
        _registerIncentiveTokens(_rootPriceOracle, chainlinkOracle);
        _registerCurveSet1(_rootPriceOracle, curveV1Oracle);

        _rootPriceOracle.setSafeSpotPriceThreshold(WETH_MAINNET, 200);
        _rootPriceOracle.setSafeSpotPriceThreshold(CURVE_ETH, 200);
        _rootPriceOracle.setSafeSpotPriceThreshold(WSTETH_MAINNET, 200);
        _rootPriceOracle.setSafeSpotPriceThreshold(STETH_MAINNET, 200);
    }

    function _registerIncentiveTokens(RootPriceOracle rootPriceOracle, ChainlinkOracle chainlinkOracle) internal {
        address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address ldo = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

        rootPriceOracle.registerMapping(crv, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(cvx, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(ldo, IPriceOracle(chainlinkOracle));
    }

    function _registerCurveSet1(RootPriceOracle rootPriceOracle, CurveV1StableEthOracle curveV1Oracle) internal {
        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        curveV1Oracle.registerPool(curveStEthNgPool, curveStEthNgLpToken);
        rootPriceOracle.registerPoolMapping(curveStEthNgPool, curveV1Oracle);
    }

    function _registerBaseTokens(RootPriceOracle rootPriceOracle, ChainlinkOracle chainlinkOracle) internal {
        WstETHEthOracle wstEthOracle = new WstETHEthOracle(_systemRegistry, WSTETH_MAINNET);

        EthPeggedOracle ethPegOracle = new EthPeggedOracle(_systemRegistry);

        chainlinkOracle.registerOracle(
            STETH_MAINNET,
            IAggregatorV3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        rootPriceOracle.registerMapping(STETH_MAINNET, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(WSTETH_MAINNET, IPriceOracle(wstEthOracle));
        rootPriceOracle.registerMapping(WETH_MAINNET, IPriceOracle(ethPegOracle));
        rootPriceOracle.registerMapping(CURVE_ETH, IPriceOracle(ethPegOracle));
    }

    function _setupAutopool() internal {
        AutopoolETHStrategyConfig.StrategyConfig memory strategyConfig = AutopoolETHStrategyConfig.StrategyConfig({
            swapCostOffset: AutopoolETHStrategyConfig.SwapCostOffsetConfig({
                initInDays: 28,
                tightenThresholdInViolations: 5,
                tightenStepInDays: 3,
                relaxThresholdInDays: 20,
                relaxStepInDays: 3,
                maxInDays: 60,
                minInDays: 10
            }),
            navLookback: AutopoolETHStrategyConfig.NavLookbackConfig({
                lookback1InDays: 30,
                lookback2InDays: 60,
                lookback3InDays: 90
            }),
            slippage: AutopoolETHStrategyConfig.SlippageConfig({
                maxNormalOperationSlippage: 1e16, // 1%
                maxTrimOperationSlippage: 2e16, // 2%
                maxEmergencyOperationSlippage: 0.025e18, // 2.5%
                maxShutdownOperationSlippage: 0.015e18 // 1.5%
             }),
            modelWeights: AutopoolETHStrategyConfig.ModelWeights({
                baseYield: 1e6,
                feeYield: 1e6,
                incentiveYield: 0.9e6,
                priceDiscountExit: 0.75e6,
                priceDiscountEnter: 0,
                pricePremium: 1e6
            }),
            pauseRebalancePeriodInDays: 90,
            rebalanceTimeGapInSeconds: 3600, // 1 hours
            maxPremium: 0.01e18, // 1%
            maxDiscount: 0.02e18, // 2%
            staleDataToleranceInSeconds: 2 days,
            maxAllowedDiscount: 0.05e18,
            lstPriceGapTolerance: 10, // 10 bps
            hooks: [address(0), address(0), address(0), address(0), address(0)]
        });

        // Configure Autopool template and factory
        address autoPoolTemplate = address(new AutopoolETH(_systemRegistry, WETH_MAINNET));
        _autopoolFactory = new AutopoolFactory(_systemRegistry, autoPoolTemplate, 800, 100);
        _accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(_autopoolFactory));
        _accessController.grantRole(Roles.AUTO_POOL_FACTORY_MANAGER, address(this));

        // Configure Strategy
        AutopoolETHStrategy strategyTemplate = new AutopoolETHStrategy(_systemRegistry, strategyConfig);
        _autopoolFactory.addStrategyTemplate(address(strategyTemplate));

        // Create Autopool
        bytes32 autoPoolSalt = keccak256(abi.encode("autoPool1"));
        vm.deal(address(this), 10e18);
        _pool = AutopoolETH(
            address(
                _autopoolFactory.createVault{ value: 100_000 }(
                    address(strategyTemplate), "X", "X", autoPoolSalt, abi.encode("")
                )
            )
        );
    }

    function _setupCurveConvexDestinationTemplate() internal {
        bytes32 dvType = keccak256(abi.encode("curve-convex"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        if (!_destinationTemplateRegistry.isWhitelistedDestination(dvType)) {
            _destinationTemplateRegistry.addToWhitelist(dvTypes);
        }

        address defaultStakingTokenCvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CurveConvexDestinationVault dv =
            new CurveConvexDestinationVault(_systemRegistry, defaultStakingTokenCvx, convexBooster);

        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        _destinationTemplateRegistry.register(dvTypes, dvs);
    }

    function _deployStEthEthNgSetupData() internal returns (DestinationVault) {
        address lpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address pool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        address calculator = _mockCurveConvexDestinationVaultCalculator(lpToken, pool);
        return _deployCurveConvexDestinationVault(
            "curve-convex", calculator, lpToken, pool, 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8, 177
        );
    }

    function _mockCurveConvexDestinationVaultCalculator(address lpToken, address pool) internal returns (address) {
        address calculator = makeAddr(string.concat("calculator", string(abi.encode(_saltIx++))));
        vm.mockCall(calculator, abi.encodeWithSignature("lpToken()"), abi.encode(lpToken));
        vm.mockCall(calculator, abi.encodeWithSignature("pool()"), abi.encode(pool));
        return calculator;
    }

    function _deployCurveConvexDestinationVault(
        string memory template,
        address calculator,
        address curvePool,
        address curvePoolLpToken,
        address convexStaking,
        uint256 convexPoolId
    ) internal returns (DestinationVault) {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: curvePool,
            convexStaking: convexStaking,
            convexPoolId: convexPoolId
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            _destinationVaultFactory.create(
                template,
                WETH_MAINNET,
                curvePoolLpToken,
                calculator,
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, _saltIx++)),
                initParamBytes
            )
        );

        return DestinationVault(newVault);
    }
}

contract UpdateDebtReporting is AutopoolFullDeployTests {
    function setUp() public {
        _setUp(19_832_815);
    }

    function test_DebtReportingCapturesAllAutoCompoundedRewards() public {
        address user = makeAddr("user1");

        // Give our user some funds to work with
        deal(user, 200e18);

        vm.startPrank(user);

        _weth.deposit{ value: 100e18 }();
        _weth.approve(address(_pool), 100e18);

        // Deposit into the Autopool so we have some idle to deploy
        _pool.deposit(100e18, user);

        vm.stopPrank();

        // Give our Solver some tokens to use in the rebalance
        uint256 inAmount = 400e18;
        deal(_curveStEthNgDv.underlying(), address(_solver), inAmount);

        // Mock good stats so the rebalance go through, really high fee apr
        address[] memory emptyAddrAr = new address[](0);
        uint256[] memory emptyUint256Ar = new uint256[](0);
        uint40[] memory emptyUint40Ar = new uint40[](0);

        IDexLSTStats.StakingIncentiveStats memory stakingStats = IDexLSTStats.StakingIncentiveStats({
            safeTotalSupply: 1e18,
            rewardTokens: emptyAddrAr,
            annualizedRewardAmounts: emptyUint256Ar,
            periodFinishForRewards: emptyUint40Ar,
            incentiveCredits: 0
        });
        ILSTStats.LSTStatsData[] memory emptyLstStats = new ILSTStats.LSTStatsData[](0);
        IDexLSTStats.DexLSTStatsData memory stats = IDexLSTStats.DexLSTStatsData({
            lastSnapshotTimestamp: block.timestamp - 10,
            feeApr: 100e18,
            reservesInEth: emptyUint256Ar,
            stakingIncentiveStats: stakingStats,
            lstStatsData: emptyLstStats
        });
        vm.mockCall(address(_curveStEthNgDv.getStats()), abi.encodeWithSignature("current()"), abi.encode(stats));

        // Perform rebalance

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_curveStEthNgDv),
            tokenIn: _curveStEthNgDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_pool),
            tokenOut: address(WETH_MAINNET),
            amountOut: 100e18
        });

        _pool.flashRebalance(
            IERC3156FlashBorrower(_solver), rebalanceParams, abi.encode(inAmount, _curveStEthNgDv.underlying())
        );

        assertEq(_curveStEthNgDv.balanceOf(address(_pool)), inAmount, "dvBal");

        // At this point we have LP staked in Convex, mimic some auto compounded rewards
        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));
        deal(address(this), 200e18);
        _weth.deposit{ value: 200e18 }();
        _weth.approve(address(_curveStEthNgDv.rewarder()), 200e18);
        IBaseRewarder(_curveStEthNgDv.rewarder()).queueNewRewards(200e18);

        // Jump ahead in time so that our Autopool would have earned some of those rewards
        vm.roll(block.number + 1000);

        uint256 snapshotId = vm.snapshot();

        // Perform a debt reporting which should see our rewards claimed to idle
        // 1e5, We have idle hanging our from our initialization
        assertEq(_pool.getAssetBreakdown().totalIdle, 1e5, "preIdle");
        _accessController.grantRole(Roles.AUTO_POOL_REPORTING_EXECUTOR, address(this));
        _pool.updateDebtReporting(5);
        assertEq(_pool.getAssetBreakdown().totalIdle, 200e18 + 1e5, "postIdle");
        assertEq(_weth.balanceOf(address(_pool)), 200e18 + 1e5, "postBal");

        // So we've seen without any interaction in the Autopool we claim that 200 rewards
        // into idle. Now, revert to before we did the debt reporting and we'll do a withdraw
        // before the debt reporting

        vm.revertTo(snapshotId);

        vm.startPrank(user);
        _pool.redeem(10e18, user, user);
        vm.stopPrank();

        // Had some positive slippage from the swap so it dropped into idle
        uint256 positiveSlippage = 1_832_874_870_245_179;

        // Perform the debt reporting again and ensure we have matching idle
        // and balances (accounting for our positive slippage);
        assertEq(_pool.getAssetBreakdown().totalIdle, positiveSlippage, "pass2Idle");
        _accessController.grantRole(Roles.AUTO_POOL_REPORTING_EXECUTOR, address(this));
        _pool.updateDebtReporting(5);
        assertEq(_pool.getAssetBreakdown().totalIdle, 200e18 + positiveSlippage, "pass2Idle");
        assertEq(_weth.balanceOf(address(_pool)), 200e18 + positiveSlippage, "pass2Bal");
    }
}

contract FundedSolver is IERC3156FlashBorrower {
    constructor() { }

    function onFlashLoan(address, address, uint256, uint256, bytes memory data) external returns (bytes32) {
        (uint256 ret, address token) = abi.decode(data, (uint256, address));

        IERC20(token).transfer(msg.sender, ret);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
