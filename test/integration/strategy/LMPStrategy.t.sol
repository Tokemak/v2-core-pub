// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
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
import { LMPVaultFactory } from "src/vault/LMPVaultFactory.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { LMPStrategyConfig } from "src/strategy/LMPStrategyConfig.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";

contract LMPStrategyInt is Test {
    address constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

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

    LMPVaultRegistry _lmpVaultRegistry;
    LMPVaultFactory _lmpVaultFactory;

    LMPVault _vault;

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

        vm.deal(V2_DEPLOYER, 1000e18);
        vm.startPrank(V2_DEPLOYER);

        _systemRegistry.addRewardToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH

        _destRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destRegistry));

        _destVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _systemRegistry.setDestinationVaultRegistry(address(_destVaultRegistry));

        _destVaultFactory = new DestinationVaultFactory(_systemRegistry, defaultRewardRatio, defaultRewardBlockDuration);
        _destVaultRegistry.setVaultFactory(address(_destVaultFactory));

        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, V2_DEPLOYER);

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

        _lmpVaultRegistry = new LMPVaultRegistry(_systemRegistry);
        _systemRegistry.setLMPVaultRegistry(address(_lmpVaultRegistry));

        address lmpTemplate = address(new LMPVault(_systemRegistry, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        _lmpVaultFactory = new LMPVaultFactory(_systemRegistry, lmpTemplate, 800, 100);

        _accessController.grantRole(Roles.REGISTRY_UPDATER, address(_lmpVaultFactory));
        _accessController.grantRole(Roles.CREATE_POOL_ROLE, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULTS_UPDATER, V2_DEPLOYER);
        _accessController.grantRole(Roles.SOLVER_ROLE, address(this));

        bytes32 lmpSalt = keccak256(abi.encode("lmp1"));
        address lmpVaultAddress = Clones.predictDeterministicAddress(lmpTemplate, lmpSalt, address(_lmpVaultFactory));

        _strategy = new ValueCheckingStrategy(_systemRegistry, lmpVaultAddress, getDefaultConfig());

        LMPVault.ExtraData memory extraData = LMPVault.ExtraData({ lmpStrategyAddress: address(_strategy) });

        _vault = LMPVault(
            address(
                _lmpVaultFactory.createVault(
                    type(uint112).max, type(uint112).max, "X", "X", lmpSalt, abi.encode(extraData)
                )
            )
        );

        address[] memory destinations = new address[](2);
        destinations[0] = address(_stEthOriginalDv);
        destinations[1] = address(_stEthNgDv);

        _vault.addDestinations(destinations);

        weth.deposit{ value: 100e18 }();
        weth.approve(address(_vault), 100e18);
        _vault.deposit(100e18, V2_DEPLOYER);

        _accToke = new AccToke(
            _systemRegistry,
            //solhint-disable-next-line not-rely-on-time
            block.timestamp, // start epoch
            30 days
        );

        vm.mockCall(
            address(_systemRegistry), abi.encodeWithSelector(SystemRegistry.accToke.selector), abi.encode(_accToke)
        );

        vm.stopPrank();

        _tokenReturnSolver = new TokenReturnSolver();
    }

    function test_Construction() public {
        assertTrue(address(_vault) != address(0), "vaultAddress");
        assertEq(_vault.balanceOf(V2_DEPLOYER), 100e18, "userBal");
        assertEq(_vault.totalIdle(), 100e18, "totalIdle");
    }

    function test_IdleToCurveNg() public {
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

    function test_IdleToCurveStEthOrig() public {
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

        uint256 inLpTokenPrice = _rootPriceOracle.getPriceInEth(underlying);
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

    function test_IdleToCurveToCurve() public {
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
        uint256 outLpTokenPrice = _rootPriceOracle.getPriceInEth(outUnderlying);

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

        vm.expectRevert(abi.encodeWithSelector(ValueCheckingStrategy.BadOutPrice.selector));
        _vault.flashRebalance(
            IERC3156FlashBorrower(_tokenReturnSolver), rebalanceParams, abi.encode(inAmount, outUnderlying)
        );
    }

    function test_IdleToCurveToIdle() public {
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

        inAmount = 99e18;

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

        assertEq(_vault.totalIdle(), inAmount, "vaultBal");
    }

    function _deployCurveDestinationVault(
        string memory template,
        address calculator,
        address curvePool,
        address curvePoolLpToken,
        address convexStaking,
        uint256 convexPoolId,
        uint256 baseAssetBurnTokenIndex
    ) internal returns (DestinationVault) {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: curvePool,
            convexStaking: convexStaking,
            convexPoolId: convexPoolId,
            baseAssetBurnTokenIndex: baseAssetBurnTokenIndex
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
            25,
            1 // TODO double check this
        );
    }

    function _deployStEthEthNgSetupData() internal returns (DestinationVault) {
        return _deployCurveDestinationVault(
            "curve-convex",
            0x79CEDe27000De4Cd5c7cC270BF6d26a9425ec1BB,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
            177,
            1 // TODO double check this
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
            maxPremium: 0.01e18, // 1%
            maxDiscount: 0.02e18, // 2%
            staleDataToleranceInSeconds: 2 days,
            maxAllowedDiscount: 0.05e18,
            lstPriceGapTolerance: 10 // 10 bps
         });
    }
}

contract ValueCheckingStrategy is LMPStrategy, Test {
    uint256 private _checkInLpPrice;
    uint256 private _checkOutLpPrice;

    error BadInPrice();
    error BadOutPrice();

    constructor(
        ISystemRegistry _systemRegistry,
        address _lmpVault,
        LMPStrategyConfig.StrategyConfig memory conf
    ) LMPStrategy(_systemRegistry, _lmpVault, conf) { }

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
