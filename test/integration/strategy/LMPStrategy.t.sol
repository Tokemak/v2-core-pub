// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase,max-states-count,no-console,state-visibility,max-line-length,
// solhint-disable avoid-low-level-calls,gas-custom-errors

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { AutoPoolFactory } from "src/vault/AutoPoolFactory.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { AutoPoolRegistry } from "src/vault/AutoPoolRegistry.sol";
import { AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { CurveV1StableEthOracle } from "src/oracles/providers/CurveV1StableEthOracle.sol";
import { CurveV2CryptoEthOracle } from "src/oracles/providers/CurveV2CryptoEthOracle.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";

contract LMPStrategyInt is Test {
    address constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    address constant STETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CBETH_MAINNET = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant STETH_CL_FEED_MAINNET = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant RETH_CL_FEED_MAINNET = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant CBETH_CL_FEED_MAINNET = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant WETH9_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 public constant WETH_INIT_DEPOSIT = 100_000;

    uint256 internal saltIx = 0;
    address internal user1;
    IWETH9 internal weth;

    uint256 public defaultRewardBlockDuration = 1000;
    uint256 public defaultRewardRatio = 1;

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    DestinationRegistry _destRegistry;
    DestinationVaultRegistry _destVaultRegistry;
    DestinationVaultFactory _destVaultFactory;
    IRootPriceOracle _rootPriceOracle;

    DestinationVault _stEthOriginalDv;
    DestinationVault _stEthNgDv;

    AutoPoolRegistry _autoPoolRegistry;
    AutoPoolFactory _autoPoolFactory;

    AutoPoolETH _vault;

    TokenReturnSolver _tokenReturnSolver;
    AccToke _accToke;
    ValueCheckingStrategy _strategy;

    uint256 minStakingDuration = 30 days;

    function setUp() public {
        user1 = makeAddr("user1");
        vm.deal(user1, 1000e18);

        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_271_246);
        vm.selectFork(forkId);

        weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);
        _accessController = AccessController(address(_systemRegistry.accessController()));
        _rootPriceOracle = _systemRegistry.rootPriceOracle();

        RootPriceOracle newOracleCode = new RootPriceOracle(_systemRegistry);
        vm.etch(address(_rootPriceOracle), address(newOracleCode).code);

        vm.deal(V2_DEPLOYER, 1000e18);
        vm.startPrank(V2_DEPLOYER);

        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, V2_DEPLOYER);
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, V2_DEPLOYER);
        _accessController.grantRole(Roles.DESTINATION_VAULT_MANAGER, V2_DEPLOYER);
        _accessController.grantRole(Roles.ORACLE_MANAGER, V2_DEPLOYER);

        _systemRegistry.addRewardToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH

        _destRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destRegistry));

        _destVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _systemRegistry.setDestinationVaultRegistry(address(_destVaultRegistry));

        _destVaultFactory = new DestinationVaultFactory(_systemRegistry, defaultRewardRatio, defaultRewardBlockDuration);
        _destVaultRegistry.setVaultFactory(address(_destVaultFactory));

        // Setup Curve Convex Templates
        bytes32 dvType = keccak256(abi.encode("curve-convex"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        if (!_destRegistry.isWhitelistedDestination(dvType)) {
            _destRegistry.addToWhitelist(dvTypes);
        }

        // Setup some Curve Destinations

        // Tokens are CVX and the Convex Booster
        CurveConvexDestinationVault dv = new CurveConvexDestinationVault(
            _systemRegistry, 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
        );

        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        _destRegistry.register(dvTypes, dvs);

        _stEthOriginalDv = _deployStEthEthOriginalSetupData();
        _stEthNgDv = _deployStEthEthNgSetupData();

        // Setup the LMP Vaults

        _autoPoolRegistry = new AutoPoolRegistry(_systemRegistry);
        (bool success,) = address(_systemRegistry).call(
            abi.encodeWithSignature("setLMPVaultRegistry(address)", address(_autoPoolRegistry))
        );
        if (!success) {
            revert("fail set registry");
        }

        vm.mockCall(
            address(SYSTEM_REGISTRY),
            abi.encodeWithSelector(ISystemRegistry.autoPoolRegistry.selector),
            abi.encode(address(_autoPoolRegistry))
        );

        //_systemRegistry.setAutoPoolRegistry(address(_autoPoolRegistry));

        address autoPoolTemplate =
            address(new AutoPoolETH(_systemRegistry, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, false));
        _autoPoolFactory = new AutoPoolFactory(_systemRegistry, autoPoolTemplate, 800, 100);

        _accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(_autoPoolFactory));
        _accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, address(this));
        _accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, V2_DEPLOYER);
        _accessController.grantRole(Roles.SOLVER, address(this));

        bytes32 autoPoolSalt = keccak256(abi.encode("autoPool1"));
        address autoPoolAddress =
            Clones.predictDeterministicAddress(autoPoolTemplate, autoPoolSalt, address(_autoPoolFactory));

        ValueCheckingStrategy _strategyTemplate =
            new ValueCheckingStrategy(_systemRegistry, autoPoolAddress, getDefaultConfig());

        _autoPoolFactory.addStrategyTemplate(address(_strategyTemplate));

        _vault = AutoPoolETH(
            address(
                _autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                    address(_strategyTemplate), "X", "X", autoPoolSalt, abi.encode("")
                )
            )
        );

        _strategy = ValueCheckingStrategy(address(_vault.autoPoolStrategy()));

        address[] memory destinations = new address[](2);
        destinations[0] = address(_stEthOriginalDv);
        destinations[1] = address(_stEthNgDv);

        _vault.addDestinations(destinations);

        _accessController.grantRole(Roles.AUTO_POOL_MANAGER, V2_DEPLOYER);
        _vault.toggleAllowedUser(V2_DEPLOYER);
        _vault.toggleAllowedUser(address(this));

        weth.deposit{ value: 100e18 }();
        weth.approve(address(_vault), 100e18);
        _vault.deposit(100e18, V2_DEPLOYER);

        _accToke = new AccToke(
            _systemRegistry,
            //solhint-disable-next-line not-rely-on-time
            block.timestamp, // start epoch
            30 days
        );

        CurveResolverMainnet curveResolver =
            new CurveResolverMainnet(ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC));
        _systemRegistry.setCurveResolver(address(curveResolver));

        _setupOracles(_systemRegistry);

        vm.stopPrank();

        _tokenReturnSolver = new TokenReturnSolver();
    }

    function test_Construction() public {
        assertTrue(address(_vault) != address(0), "vaultAddress");
        assertEq(_vault.balanceOf(V2_DEPLOYER), 100e18, "userBal");
        assertEq(_vault.getAssetBreakdown().totalIdle, 100e18 + WETH_INIT_DEPOSIT, "totalIdle");
    }

    function test_FullIdleToCurveNg() public {
        uint256 inAmount = 400e18;
        deal(_stEthNgDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthNgDv),
            tokenIn: _stEthNgDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthNgDv.underlying()))
        );

        assertEq(_stEthNgDv.balanceOf(address(_vault)), inAmount, "dvBal");
    }

    function test_PartialIdleToCurveNg() public {
        uint256 inAmount = 400e18;
        deal(_stEthNgDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthNgDv),
            tokenIn: _stEthNgDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 50e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthNgDv.underlying()))
        );

        assertEq(_stEthNgDv.balanceOf(address(_vault)), inAmount, "dvBal");
    }

    function test_FullIdleToCurveStEthOrig() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        address underlying = _stEthOriginalDv.underlying();

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: underlying,
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        uint256 snapshotId = vm.snapshot();

        uint256 inLpTokenPrice = _stEthOriginalDv.getValidatedSafePrice();
        _strategy.setCheckInLpPrice(inLpTokenPrice);

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, underlying)
        );

        assertEq(_stEthOriginalDv.balanceOf(address(_vault)), inAmount, "dvBal");

        // Just testing that the price check hook is working
        vm.revertTo(snapshotId);

        _strategy.setCheckInLpPrice(2);

        vm.expectRevert(abi.encodeWithSelector(ValueCheckingStrategy.BadInPrice.selector));
        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, underlying)
        );
    }

    function test_PartialIdleToCurveStEthOrig() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        address underlying = _stEthOriginalDv.underlying();

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: underlying,
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 50e18
        });

        uint256 snapshotId = vm.snapshot();

        uint256 inLpTokenPrice = _stEthOriginalDv.getValidatedSafePrice();
        _strategy.setCheckInLpPrice(inLpTokenPrice);

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, underlying)
        );

        assertEq(_stEthOriginalDv.balanceOf(address(_vault)), inAmount, "dvBal");

        // Just testing that the price check hook is working
        vm.revertTo(snapshotId);

        _strategy.setCheckInLpPrice(2);

        vm.expectRevert(abi.encodeWithSelector(ValueCheckingStrategy.BadInPrice.selector));
        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, underlying)
        );
    }

    function test_FullIdleToCurvePartialExitToCurve() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: _stEthOriginalDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthOriginalDv.underlying()))
        );

        deal(_stEthNgDv.underlying(), address(_tokenReturnSolver), inAmount);

        address outUnderlying = _stEthOriginalDv.underlying();
        uint256 outLpTokenPrice = _stEthOriginalDv.getValidatedSafePrice();

        vm.warp(block.timestamp + 1 hours);

        uint256 snapshotId = vm.snapshot();

        _strategy.setCheckOutLpPrice(outLpTokenPrice);

        rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthNgDv),
            tokenIn: _stEthNgDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_stEthOriginalDv),
            tokenOut: outUnderlying,
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthNgDv.underlying()))
        );

        assertEq(_stEthNgDv.balanceOf(address(_vault)), inAmount, "dvBal");

        // Just testing that the price check hook is working for out
        vm.revertTo(snapshotId);

        _strategy.setCheckOutLpPrice(2);

        address ngUnderlying = _stEthNgDv.underlying();
        vm.expectRevert(abi.encodeWithSelector(ValueCheckingStrategy.BadOutPrice.selector));
        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, ngUnderlying)
        );
    }

    function test_PartialIdleToCurvePartialExitToCurve() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: _stEthOriginalDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 50e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthOriginalDv.underlying()))
        );

        deal(_stEthNgDv.underlying(), address(_tokenReturnSolver), inAmount);

        address outUnderlying = _stEthOriginalDv.underlying();
        uint256 outLpTokenPrice = _stEthOriginalDv.getValidatedSafePrice();

        vm.warp(block.timestamp + 1 hours);

        _strategy.setCheckOutLpPrice(outLpTokenPrice);

        rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthNgDv),
            tokenIn: _stEthNgDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_stEthOriginalDv),
            tokenOut: outUnderlying,
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthNgDv.underlying()))
        );

        assertEq(_stEthNgDv.balanceOf(address(_vault)), inAmount, "dvBal");
    }

    function test_FullIdleToCurveFullExitToCurve() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: _stEthOriginalDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthOriginalDv.underlying()))
        );

        uint256 additionalLp = 27e18;

        deal(_stEthNgDv.underlying(), address(_tokenReturnSolver), inAmount + additionalLp);

        address outUnderlying = _stEthOriginalDv.underlying();
        uint256 outLpTokenPrice = _stEthOriginalDv.getValidatedSafePrice();

        vm.warp(block.timestamp + 1 hours);

        _strategy.setCheckOutLpPrice(outLpTokenPrice);

        rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthNgDv),
            tokenIn: _stEthNgDv.underlying(),
            amountIn: inAmount + additionalLp,
            destinationOut: address(_stEthOriginalDv),
            tokenOut: outUnderlying,
            amountOut: inAmount
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount + additionalLp, address(_stEthNgDv.underlying()))
        );

        assertEq(_stEthNgDv.balanceOf(address(_vault)), inAmount + additionalLp, "dvBal");
    }

    function test_FullIdleToCurvePartialExitToIdle() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: _stEthOriginalDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthOriginalDv.underlying()))
        );

        inAmount = 107e18;

        deal(address(weth), address(_tokenReturnSolver), inAmount);

        rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_vault),
            tokenIn: address(weth),
            amountIn: inAmount,
            destinationOut: address(_stEthOriginalDv),
            tokenOut: _stEthOriginalDv.underlying(),
            amountOut: 100e18
        });

        vm.prank(V2_DEPLOYER);
        _stEthOriginalDv.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, address(weth))
        );

        assertEq(_vault.getAssetBreakdown().totalIdle, inAmount + WETH_INIT_DEPOSIT, "vaultBal");
    }

    function test_FullIdleToCurveFullExitToIdle() public {
        uint256 inAmount = 400e18;
        deal(_stEthOriginalDv.underlying(), address(_tokenReturnSolver), inAmount);

        IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_stEthOriginalDv),
            tokenIn: _stEthOriginalDv.underlying(),
            amountIn: inAmount,
            destinationOut: address(_vault),
            tokenOut: address(weth),
            amountOut: 100e18
        });

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver),
            rebalanceParams,
            abi.encode(inAmount, address(_stEthOriginalDv.underlying()))
        );

        inAmount = 4 * 107e18;

        deal(address(weth), address(_tokenReturnSolver), inAmount);

        rebalanceParams = IStrategy.RebalanceParams({
            destinationIn: address(_vault),
            tokenIn: address(weth),
            amountIn: inAmount,
            destinationOut: address(_stEthOriginalDv),
            tokenOut: _stEthOriginalDv.underlying(),
            amountOut: 400e18
        });

        vm.prank(V2_DEPLOYER);
        _stEthOriginalDv.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);

        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, address(weth))
        );

        assertEq(_vault.getAssetBreakdown().totalIdle, inAmount + WETH_INIT_DEPOSIT, "vaultBal");
    }

    function test_IdleCantLeaveIfShutdown() public {
        // TODO
    }

    function test_IdleInWorksEvenIfVaultShutdown() public {
        // TODO
    }

    function test_RebalanceDoesNotClaimDestinationRewards() public {
        // TODO
    }

    function _deployCurveDestinationVault(
        string memory template,
        address calculator,
        address curvePool,
        address curvePoolLpToken,
        address convexStaking,
        uint256 convexPoolId
    ) internal returns (DestinationVault) {
        // We are forked and running against a version of the calculators the destination vaults
        // don't expect. Shim the differences
        ConvexCalculator calcTemplate = new ConvexCalculator(_systemRegistry, ConvexCalculator(calculator).BOOSTER());
        vm.etch(calculator, address(calcTemplate).code);
        // 12 and 13, current slots of lpToken() and pool()
        vm.store(calculator, bytes32(uint256(12)), bytes32(uint256(uint160(curvePoolLpToken))));
        vm.store(calculator, bytes32(uint256(13)), bytes32(uint256(uint160(curvePool))));

        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: curvePool,
            convexStaking: convexStaking,
            convexPoolId: convexPoolId
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            _destVaultFactory.create(
                template,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                curvePoolLpToken,
                calculator,
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        return DestinationVault(newVault);
    }

    function _deployStEthEthOriginalSetupData() internal returns (DestinationVault) {
        return _deployCurveDestinationVault(
            "curve-convex",
            0x75177CC3f4A4724Fda3d5a0f28ab78c2654B53d1,
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0x06325440D014e39736583c165C2963BA99fAf14E,
            0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
            25
        );
    }

    function _deployStEthEthNgSetupData() internal returns (DestinationVault) {
        return _deployCurveDestinationVault(
            "curve-convex",
            0x79CEDe27000De4Cd5c7cC270BF6d26a9425ec1BB,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
            177
        );
    }

    function getDefaultConfig() internal pure returns (LMPStrategyConfig.StrategyConfig memory) {
        return LMPStrategyConfig.StrategyConfig({
            swapCostOffset: LMPStrategyConfig.SwapCostOffsetConfig({
                initInDays: 28,
                tightenThresholdInViolations: 5,
                tightenStepInDays: 3,
                relaxThresholdInDays: 20,
                relaxStepInDays: 3,
                maxInDays: 60,
                minInDays: 10
            }),
            navLookback: LMPStrategyConfig.NavLookbackConfig({
                lookback1InDays: 30,
                lookback2InDays: 60,
                lookback3InDays: 90
            }),
            slippage: LMPStrategyConfig.SlippageConfig({
                maxNormalOperationSlippage: 1e16, // 1%
                maxTrimOperationSlippage: 2e16, // 2%
                maxEmergencyOperationSlippage: 0.025e18, // 2.5%
                maxShutdownOperationSlippage: 0.015e18 // 1.5%
             }),
            modelWeights: LMPStrategyConfig.ModelWeights({
                baseYield: 1e6,
                feeYield: 1e6,
                incentiveYield: 0.9e6,
                slashing: 1e6,
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
            lstPriceGapTolerance: 10 // 10 bps
         });
    }

    function _setupOracles(SystemRegistry systemRegistry) internal {
        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        CurveV1StableEthOracle curveV1Oracle =
            new CurveV1StableEthOracle(systemRegistry, systemRegistry.curveResolver());
        CurveV2CryptoEthOracle curveV2Oracle =
            new CurveV2CryptoEthOracle(systemRegistry, systemRegistry.curveResolver());
        BalancerLPMetaStableEthOracle balancerMetaOracle = new BalancerLPMetaStableEthOracle(
            systemRegistry, IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8)
        );

        _registerBaseTokens(rootPriceOracle);
        _registerIncentiveTokens(rootPriceOracle);
        _registerBalancerMeta(rootPriceOracle, balancerMetaOracle);
        _registerCurveSet2(rootPriceOracle, curveV2Oracle);
        _registerCurveSet1(rootPriceOracle, curveV1Oracle);

        rootPriceOracle.setSafeSpotPriceThreshold(RETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WETH9_ADDRESS, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CURVE_ETH, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(CBETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(WSTETH_MAINNET, 200);
        rootPriceOracle.setSafeSpotPriceThreshold(STETH_MAINNET, 200);
    }

    function _registerBaseTokens(RootPriceOracle rootPriceOracle) internal {
        address wstEthOracle = 0xA93F316ef40848AeaFCd23485b6044E7027b5890;
        address ethPegOracle = 0x58374B8fF79f4C40Fb66e7ca8B13A08992125821;
        address chainlinkOracle = 0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72;

        console.log("Registering base tokens");
        console.log(msg.sender);
        console.log(address(this));
        rootPriceOracle.registerMapping(STETH_MAINNET, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(WSTETH_MAINNET, IPriceOracle(wstEthOracle));
        rootPriceOracle.registerMapping(WETH9_ADDRESS, IPriceOracle(ethPegOracle));
        rootPriceOracle.registerMapping(CURVE_ETH, IPriceOracle(ethPegOracle));
    }

    function _registerIncentiveTokens(RootPriceOracle rootPriceOracle) internal {
        address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address ldo = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        address chainlinkOracle = 0x70975337525D8D4Cae2deb3Ec896e7f4b9fAaB72;

        rootPriceOracle.registerMapping(crv, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(cvx, IPriceOracle(chainlinkOracle));
        rootPriceOracle.registerMapping(ldo, IPriceOracle(chainlinkOracle));
    }

    function _registerBalancerMeta(
        RootPriceOracle rootPriceOracle,
        BalancerLPMetaStableEthOracle balMetaOracle
    ) internal {
        // wstETH/WETH - Balancer Meta
        address wstEthWethBalMeta = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        // wstETH/cbETH - Balancer Meta
        address wstEthCbEthBal = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        // rEth/WETH - Balancer Meta
        address rEthWethBalMeta = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

        rootPriceOracle.registerPoolMapping(wstEthWethBalMeta, balMetaOracle);
        rootPriceOracle.registerPoolMapping(wstEthCbEthBal, balMetaOracle);
        rootPriceOracle.registerPoolMapping(rEthWethBalMeta, balMetaOracle);
    }

    function _registerCurveSet2(RootPriceOracle rootPriceOracle, CurveV2CryptoEthOracle curveV2Oracle) internal {
        address curveV2RethEthPool = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
        address curveV2RethEthLpToken = 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C;

        curveV2Oracle.registerPool(curveV2RethEthPool, curveV2RethEthLpToken);
        rootPriceOracle.registerPoolMapping(curveV2RethEthPool, curveV2Oracle);

        address curveV2cbEthEthPool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
        address curveV2cbEthEthLpToken = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;

        curveV2Oracle.registerPool(curveV2cbEthEthPool, curveV2cbEthEthLpToken);
        rootPriceOracle.registerPoolMapping(curveV2cbEthEthPool, curveV2Oracle);
    }

    function _registerCurveSet1(RootPriceOracle rootPriceOracle, CurveV1StableEthOracle curveV1Oracle) internal {
        address curveStEthOriginalPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        address curveStEthOriginalLpToken = 0x06325440D014e39736583c165C2963BA99fAf14E;

        curveV1Oracle.registerPool(curveStEthOriginalPool, curveStEthOriginalLpToken);
        rootPriceOracle.registerPoolMapping(curveStEthOriginalPool, curveV1Oracle);

        address curveStEthConcentratedPool = 0x828b154032950C8ff7CF8085D841723Db2696056;
        address curveStEthConcentratedLpToken = 0x828b154032950C8ff7CF8085D841723Db2696056;

        curveV1Oracle.registerPool(curveStEthConcentratedPool, curveStEthConcentratedLpToken);
        rootPriceOracle.registerPoolMapping(curveStEthConcentratedPool, curveV1Oracle);

        address curveStEthNgPool = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
        address curveStEthNgLpToken = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

        curveV1Oracle.registerPool(curveStEthNgPool, curveStEthNgLpToken);
        rootPriceOracle.registerPoolMapping(curveStEthNgPool, curveV1Oracle);

        address curveRethWstethPool = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveRethWstethLpToken = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;

        curveV1Oracle.registerPool(curveRethWstethPool, curveRethWstethLpToken);
        rootPriceOracle.registerPoolMapping(curveRethWstethPool, curveV1Oracle);
    }
}

contract ValueCheckingStrategy is LMPStrategy, Test {
    uint256 private _checkInLpPrice;
    uint256 private _checkOutLpPrice;

    error BadInPrice();
    error BadOutPrice();

    constructor(
        ISystemRegistry _systemRegistry,
        address _autoPool,
        LMPStrategyConfig.StrategyConfig memory conf
    ) LMPStrategy(_systemRegistry, conf) { }

    function setCheckInLpPrice(uint256 price) external {
        _checkInLpPrice = price;
    }

    function setCheckOutLpPrice(uint256 price) external {
        _checkOutLpPrice = price;
    }

    function getRebalanceInSummaryStats(IStrategy.RebalanceParams memory rebalanceParams)
        internal
        virtual
        override
        returns (IStrategy.SummaryStats memory inSummary)
    {
        inSummary = super.getRebalanceInSummaryStats(rebalanceParams);

        if (_checkInLpPrice > 0) {
            if (inSummary.pricePerShare != _checkInLpPrice) {
                revert BadInPrice();
            }
        }
    }

    function _getRebalanceOutSummaryStats(IStrategy.RebalanceParams memory rebalanceParams)
        internal
        virtual
        override
        returns (IStrategy.SummaryStats memory outSummary)
    {
        outSummary = super._getRebalanceOutSummaryStats(rebalanceParams);

        if (_checkOutLpPrice > 0) {
            if (outSummary.pricePerShare != _checkOutLpPrice) {
                revert BadOutPrice();
            }
        }
    }
}

contract TokenReturnSolver is IERC3156FlashBorrower {
    constructor() { }

    function onFlashLoan(address, address, uint256, uint256, bytes memory data) external returns (bytes32) {
        (uint256 ret, address token) = abi.decode(data, (uint256, address));

        IERC20(token).transfer(msg.sender, ret);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
