// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls

import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IRecoveryMode } from "src/interfaces/external/balancer/IRecoveryMode.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import {
    WETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL,
    STETH_MAINNET,
    BAL_VAULT,
    AURA_BOOSTER,
    WSTETH_MAINNET,
    WSETH_WETH_BAL_POOL,
    AURA_MAINNET,
    BAL_WSTETH_SFRX_ETH_RETH_WHALE,
    SFRXETH_MAINNET,
    RETH_WETH_BAL_POOL,
    RETH_MAINNET,
    BALANCER_MAINNET_AUTHORIZER
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract BalancerAuraDestinationVaultComposableTests is Test {
    address private constant LP_TOKEN_WHALE = BAL_WSTETH_SFRX_ETH_RETH_WHALE;
    address private constant AURA_STAKING = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;

    uint256 private _mainnetFork;

    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    DestinationVaultFactory private _destinationVaultFactory;
    DestinationVaultRegistry private _destinationVaultRegistry;
    DestinationRegistry private _destinationTemplateRegistry;

    ILMPVaultRegistry private _lmpVaultRegistry;
    IRootPriceOracle private _rootPriceOracle;

    IWETH9 private _asset;

    IERC20 private _underlyer;
    TestIncentiveCalculator private _testIncentiveCalculator;
    BalancerAuraDestinationVault private _destVault;

    SwapRouter private swapRouter;
    BalancerV2Swap private balSwapper;

    address[] private additionalTrackedTokens;

    function setUp() public {
        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_693_095);
        vm.selectFork(_mainnetFork);

        additionalTrackedTokens = new address[](0);

        vm.label(address(this), "testContract");

        _systemRegistry = new SystemRegistry(vm.addr(100), WETH_MAINNET);

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _asset = IWETH9(WETH_MAINNET);

        _systemRegistry.addRewardToken(WETH_MAINNET);

        // Setup swap router

        swapRouter = new SwapRouter(_systemRegistry);
        balSwapper = new BalancerV2Swap(address(swapRouter), BAL_VAULT);
        // setup input for Bal WSTETH -> WETH
        ISwapRouter.SwapData[] memory wstethSwapRoute = new ISwapRouter.SwapData[](1);
        ISwapRouter.SwapData memory wstEthWethSwapData = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: WSETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080) // wstETH/WETH pool
         });
        wstethSwapRoute[0] = wstEthWethSwapData;
        swapRouter.setSwapRoute(WSTETH_MAINNET, wstethSwapRoute);

        // setup input for Bal SFRXETH -> WETH
        ISwapRouter.SwapData[] memory sfrxEthSwapRoute = new ISwapRouter.SwapData[](2);
        sfrxEthSwapRoute[0] = ISwapRouter.SwapData({
            token: WSTETH_MAINNET,
            pool: WSETH_RETH_SFRXETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x5aee1e99fe86960377de9f88689616916d5dcabe000000000000000000000467)
        });
        sfrxEthSwapRoute[1] = wstEthWethSwapData;
        swapRouter.setSwapRoute(SFRXETH_MAINNET, sfrxEthSwapRoute);

        // setup input for Bal RETH -> WETH
        ISwapRouter.SwapData[] memory rEthSwapRoute = new ISwapRouter.SwapData[](1);
        rEthSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: RETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112)
        });
        swapRouter.setSwapRoute(RETH_MAINNET, rEthSwapRoute);

        _systemRegistry.setSwapRouter(address(swapRouter));
        vm.label(address(swapRouter), "swapRouter");
        vm.label(address(balSwapper), "balSwapper");

        // Setup the Destination system

        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _destinationTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destinationTemplateRegistry));
        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));
        _destinationVaultFactory = new DestinationVaultFactory(_systemRegistry, 1, 1000);
        _destinationVaultRegistry.setVaultFactory(address(_destinationVaultFactory));

        _underlyer = IERC20(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.label(address(_underlyer), "underlyer");

        BalancerAuraDestinationVault dvTemplate =
            new BalancerAuraDestinationVault(_systemRegistry, BAL_VAULT, AURA_MAINNET);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSETH_RETH_SFRXETH_BAL_POOL,
            auraStaking: 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 50
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator(address(_underlyer));
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

        _destVault = BalancerAuraDestinationVault(newVault);

        _rootPriceOracle = IRootPriceOracle(vm.addr(34_399));
        vm.label(address(_rootPriceOracle), "rootPriceOracle");

        _mockSystemBound(address(_systemRegistry), address(_rootPriceOracle));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));
        _mockRootPrice(address(_asset), 1 ether);
        _mockRootPrice(address(_underlyer), 2 ether);

        // Set lmp vault registry for permissions
        _lmpVaultRegistry = ILMPVaultRegistry(vm.addr(237_894));
        vm.label(address(_lmpVaultRegistry), "lmpVaultRegistry");
        _mockSystemBound(address(_systemRegistry), address(_lmpVaultRegistry));
        _systemRegistry.setLMPVaultRegistry(address(_lmpVaultRegistry));

        // Disable Pool RecoveryMode
        // Note: at the forked block pool is in RecoveryMode, we want to use pool without it
        // but withdrawals from the RecoveryMode tested specifically in
        // `withdrawBaseAsset_IsPossibleWhenPoolIsInRecoveryMode` scenario.
        IRecoveryMode pool = IRecoveryMode(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.prank(BALANCER_MAINNET_AUTHORIZER);
        pool.disableRecoveryMode();
        assertFalse(pool.inRecoveryMode());
    }

    function test_initializer_ConfiguresVault() public {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSETH_RETH_SFRXETH_BAL_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 50
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

    function test_isComposable_TrueForComposableValues() public {
        assertTrue(_destVault.isComposable());
    }

    function test_exchangeName_Returns() public {
        assertEq(_destVault.exchangeName(), "balancer");
    }

    function test_underlyingTokens_ReturnsForComposable() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 3);
        assertEq(IERC20(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20(tokens[1]).symbol(), "sfrxETH");
        assertEq(IERC20(tokens[2]).symbol(), "rETH");
    }

    function test_depositUnderlying_TokensGoToAura() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to Aura
        assertEq(_destVault.externalDebtBalance(), 10e18);
    }

    function test_withdrawUnderlying_PullsFromAura() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to Convex
        assertEq(_destVault.externalDebtBalance(), 10e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(10e18, receiver);

        assertEq(received, 10e18);
        assertEq(_underlyer.balanceOf(receiver), 10e18);
        assertEq(_destVault.externalDebtBalance(), 0e18);
    }

    function test_withdrawBaseAsset_ReturnsAppropriateAmount() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        uint256 received = _destVault.withdrawBaseAsset(10e18, receiver);

        // Bal pool has a rough pool value of $48,618,767
        // Total Supply of 24059.127967424958374618
        // Eth Price: $1977.44
        // PPS: 1.01 w/10 shares ~= 10
        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_128_444_161_444_807_958);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    function test_withdrawBaseAsset_IsPossibleWhenPoolIsInRecoveryMode() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        // Put pool into RecoveryMode
        IRecoveryMode pool = IRecoveryMode(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.prank(BALANCER_MAINNET_AUTHORIZER);
        pool.enableRecoveryMode();
        assertTrue(pool.inRecoveryMode());

        // Run withdrawal
        uint256 received = _destVault.withdrawBaseAsset(10e18, receiver);

        // Bal pool has a rough pool value of $48,618,767
        // Total Supply of 24059.127967424958374618
        // Eth Price: $1977.44
        // PPS: 1.01 w/10 shares ~= 10
        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_128_444_161_444_807_958);
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
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), localDepositAmount);

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
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        // Make sure balance of underlyer is on DV.
        assertEq(_underlyer.balanceOf(address(_destVault)), 1000);

        // Check to make sure `internalDebtBalance()` not changed. Used to be queried with `balanceOf(_destVault)`.
        assertEq(_destVault.internalDebtBalance(), 0);
    }

    function test_ExternalDebtBalance_CannotBeManipulated() external {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Approve staking.
        _underlyer.approve(AURA_STAKING, 1000);

        // Low level call to stake, no need for interface for test.
        (, bytes memory payload) =
            AURA_STAKING.call(abi.encodeWithSignature("deposit(uint256,address)", uint256(1000), address(_destVault)));
        // Check that payload returns correct amount, `deposit()` returns uint256.  If this is true no need to
        //      check call success.
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Use low level call to check balance.
        (, payload) = AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Make sure that DV not picking up external balances.
        assertEq(_destVault.externalDebtBalance(), 0);
    }

    function test_InternalQueriedBalance_CapturesUnderlyerInVault() external {
        // Transfer tokens to address.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        assertEq(_destVault.internalQueriedBalance(), 1000);
    }

    function test_ExternalQueriedBalance_CapturesUnderlyerNotStakedByVault() external {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Approve staking.
        _underlyer.approve(AURA_STAKING, 1000);

        // Low level call to stake, no need for interface for test.
        (, bytes memory payload) =
            AURA_STAKING.call(abi.encodeWithSignature("deposit(uint256,address)", uint256(1000), address(_destVault)));
        // Check that payload returns correct amount, `dep()` returns uint256.  If this is true no need to
        //      check call success.
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Use low level call to check balance.
        (, payload) = AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Make sure that DV not picking up external balances.  Used to query rewarder.
        assertEq(_destVault.externalQueriedBalance(), 1000);
    }

    function _mockSystemBound(address registry, address addr) internal {
        vm.mockCall(addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(registry));
    }

    function _mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function _mockIsVault(address vault, bool isVault) internal {
        vm.mockCall(
            address(_lmpVaultRegistry),
            abi.encodeWithSelector(ILMPVaultRegistry.isVault.selector, vault),
            abi.encode(isVault)
        );
    }
}
