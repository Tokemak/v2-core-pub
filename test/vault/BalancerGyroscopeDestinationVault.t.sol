// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import {
    WETH_MAINNET,
    WSTETH_WETH_GYRO_POOL,
    BAL_VAULT,
    BAL_MAINNET,
    AURA_BOOSTER,
    WSTETH_MAINNET,
    AURA_MAINNET,
    GYRO_WSTETH_WETH_WHALE
} from "test/utils/Addresses.sol";

import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVault, IDestinationVault } from "src/vault/DestinationVault.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { BalancerGyroscopeDestinationVault } from "src/vault/BalancerGyroscopeDestinationVault.sol";

contract BalancerGyroscopeDestinationVaultTests is Test {
    address private constant LP_TOKEN_WHALE = GYRO_WSTETH_WETH_WHALE; //~21
    address private constant AURA_STAKING = 0x35113146E7f2dF77Fb40606774e0a3F402035Ffb;

    uint256 private _mainnetFork;

    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    DestinationVaultFactory private _destinationVaultFactory;
    DestinationVaultRegistry private _destinationVaultRegistry;
    DestinationRegistry private _destinationTemplateRegistry;

    IAutopoolRegistry private _autoPoolRegistry;
    IRootPriceOracle private _rootPriceOracle;

    IWETH9 private _asset;

    IERC20 private _underlyer;

    TestIncentiveCalculator private _testIncentiveCalculator;

    BalancerGyroscopeDestinationVault private _destVault;

    SwapRouter private swapRouter;
    BalancerV2Swap private balSwapper;

    address[] private additionalTrackedTokens;

    event UnderlyerRecovered(address destination, uint256 amount);

    function setUp() public {
        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_661_436);
        vm.selectFork(_mainnetFork);
        runSetUp();
    }

    function runSetUp() public {
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
        wstethSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: WSTETH_WETH_GYRO_POOL,
            swapper: balSwapper,
            data: abi.encode(0xf01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005de) // wstETH/WETH pool
         });
        swapRouter.setSwapRoute(WSTETH_MAINNET, wstethSwapRoute);
        _systemRegistry.setSwapRouter(address(swapRouter));
        vm.label(address(swapRouter), "swapRouter");
        vm.label(address(balSwapper), "balSwapper");
        vm.label(BAL_VAULT, "balVault");
        vm.label(0xF89A1713998593A441cdA571780F0900Dbef20f9, "gyroMath");

        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));

        // Setup the Destination system

        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _destinationTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destinationTemplateRegistry));
        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));
        _destinationVaultFactory = new DestinationVaultFactory(_systemRegistry, 1, 1000);
        _destinationVaultRegistry.setVaultFactory(address(_destinationVaultFactory));

        _underlyer = IERC20(WSTETH_WETH_GYRO_POOL);
        vm.label(address(_underlyer), "underlyer");

        BalancerGyroscopeDestinationVault dvTemplate =
            new BalancerGyroscopeDestinationVault(_systemRegistry, BAL_VAULT, AURA_MAINNET);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSTETH_WETH_GYRO_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 162
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));

        additionalTrackedTokens = new address[](0);

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

        _destVault = BalancerGyroscopeDestinationVault(newVault);

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

    function test_initializer_ConfiguresVault() public {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSTETH_WETH_GYRO_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 162
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

    function test_exchangeName_Returns() public {
        assertEq(_destVault.exchangeName(), "balancer");
    }

    function test_PoolType_Returns() public {
        assertEq(_destVault.poolType(), "balGyro");
    }

    function test_underlyingTokens_ReturnsForMetastable() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20Metadata(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20Metadata(tokens[1]).symbol(), "WETH");
    }

    function test_depositUnderlying_TokensGoToAura() public {
        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to Aura
        assertEq(_destVault.externalQueriedBalance(), 10e18);
    }

    function test_depositUnderlying_TokensDoNotGoToAuraIfPoolTokensNumberChange() public {
        IERC20[] memory mockTokens = new IERC20[](1);
        mockTokens[0] = IERC20(WSTETH_MAINNET);

        uint256[] memory balances = new uint256[](1);
        balances[0] = 100;
        uint256 lastChangeBlock = block.timestamp;

        vm.mockCall(
            BAL_VAULT,
            abi.encodeWithSelector(IVault.getPoolTokens.selector),
            abi.encode(mockTokens, balances, lastChangeBlock)
        );

        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Approve and try deposit
        _underlyer.approve(address(_destVault), 10e18);

        address[] memory cachedTokens = new address[](2);
        cachedTokens[0] = WSTETH_MAINNET;
        cachedTokens[1] = WETH_MAINNET;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerAuraDestinationVault.PoolTokensChanged.selector, cachedTokens, mockTokens)
        );

        _destVault.depositUnderlying(10e18);
    }

    function test_depositUnderlying_TokensDoNotGoToAuraIfPoolTokensChange() public {
        IERC20[] memory mockTokens = new IERC20[](2);
        mockTokens[0] = IERC20(AURA_MAINNET);
        mockTokens[1] = IERC20(BAL_MAINNET);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 100;
        balances[1] = 100;
        uint256 lastChangeBlock = block.timestamp;

        vm.mockCall(
            BAL_VAULT,
            abi.encodeWithSelector(IVault.getPoolTokens.selector),
            abi.encode(mockTokens, balances, lastChangeBlock)
        );

        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Approve and try deposit
        _underlyer.approve(address(_destVault), 10e18);

        address[] memory cachedTokens = new address[](2);
        cachedTokens[0] = WSTETH_MAINNET;
        cachedTokens[1] = WETH_MAINNET;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerAuraDestinationVault.PoolTokensChanged.selector, cachedTokens, mockTokens)
        );

        _destVault.depositUnderlying(10e18);
    }

    function test_collectRewards_ReturnsAllTokensAndAmounts() public {
        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        IERC20 bal = IERC20(BAL_MAINNET);
        IERC20 aura = IERC20(AURA_MAINNET);

        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));

        uint256 preBalBAL = bal.balanceOf(address(this));
        uint256 preBalAURA = aura.balanceOf(address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 3);
        assertEq(address(tokens[0]), AURA_MAINNET);
        assertEq(address(tokens[1]), BAL_MAINNET);
        assertEq(address(tokens[2]), address(0)); // stash token

        assertTrue(amounts[0] > 0);
        assertTrue(amounts[1] > 0);

        uint256 afterBalBAL = bal.balanceOf(address(this));
        uint256 afterBalAURA = aura.balanceOf(address(this));

        assertEq(amounts[0], afterBalAURA - preBalAURA);
        assertEq(amounts[1], afterBalBAL - preBalBAL);
    }

    function test_withdrawUnderlying_PullsFromAura() public {
        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to Convex
        assertEq(_destVault.externalQueriedBalance(), 10e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(10e18, receiver);

        assertEq(received, 10e18);
        assertEq(_underlyer.balanceOf(receiver), 10e18);
        assertEq(_destVault.externalDebtBalance(), 0e18);
    }

    /**
     * @notice This test is to ensure that the `withdrawUnderlying` function reverts when the pool is skewed.
     *         We observed this behavior in the at block 19_661_436 and we want to ensure we revert in that case.
     */
    function test_withdrawBaseAsset_Reverts_On_Skewed_Pool() public {
        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);

        vm.expectRevert("GYR#357");
        _destVault.withdrawBaseAsset(10e18, receiver);
    }

    /**
     * @notice This test is to ensure that the `withdrawBaseAsset` function returns the appropriate amount when the pool
     * is not skewed.
     */
    function test_withdrawBaseAsset_ReturnsAppropriateAmount() public {
        uint256 localFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_034_555);
        vm.selectFork(localFork);

        runSetUp();

        // Get some tokens to play with
        deal(address(_underlyer), address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        (uint256 received,,) = _destVault.withdrawBaseAsset(10e18, receiver);

        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_167_536_848_304_340_295);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    //
    // Below tests test functionality introduced in response to Sherlock 625.
    // Link here: https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/invalid/625.md
    //
    function test_ExternalDebtBalance_UpdatesProperly_DepositAndWithdrawal() external {
        uint256 localDepositAmount = 1000;
        uint256 localWithdrawalAmount = 600;

        // Transfer tokens to address.
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
        // Transfer tokens to address.
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
        // Check that payload returns correct amount, `deposit()` returns uint256.  If this is true no need to
        //      check call success.
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Use low level call to check balance.
        (, payload) = AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(abi.decode(payload, (uint256)), 1000);

        // Make sure that DV not picking up external balances.  Used to query rewarder.
        assertEq(_destVault.externalQueriedBalance(), 1000);
    }

    /**
     * Below three functions test `DestinationVault.recoverUnderlying()`.  When there is an excess externally staked
     *      balance, this function interacts with the  protocol that the underlyer is staked into, making it easier
     *      to test here with a full working DV rather than the TestDestinationVault contract in
     *      `DestinationVault.t.sol`.
     */
    function test_recoverUnderlying_RunsProperly_RecoverExternal() external {
        address recoveryAddress = vm.addr(1);

        // Give contract TOKEN_RECOVERY_MANAGER.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

        // Transfer tokens to this contract.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Approve Aura to take tokens.
        _underlyer.approve(AURA_STAKING, 1000);

        // Stake in Aura.
        (, bytes memory data) =
            AURA_STAKING.call(abi.encodeWithSignature("deposit(uint256,address)", uint256(555), address(_destVault)));

        // Make sure `deposit()` returning correct amount.
        assertEq(abi.decode(data, (uint256)), 555);

        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(recoveryAddress, 555);
        _destVault.recoverUnderlying(recoveryAddress);

        // Ensure that balanceOf(address(this)) is 0 in Aura.
        (bool success, bytes memory data2) =
            AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(this)));
        assertEq(success, true);
        assertEq(abi.decode(data2, (uint256)), 0);

        // Make sure underlyer made its way to recoveryAddress.
        assertEq(_underlyer.balanceOf(recoveryAddress), 555);
    }

    // Tests to make sure that excess external debt is being calculated properly.
    function test_recoverUnderlying_RunsProperly_ExternalDebt() external {
        address recoveryAddress = vm.addr(1);

        // Give contract TOKEN_RECOVERY_MANAGER.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

        // Transfer tokens to this contract.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 2000);

        // Approve Aura to take tokens.
        _underlyer.approve(AURA_STAKING, 1000);

        // Deposit underlying through DV.
        _mockIsVault(address(this), true);
        _underlyer.approve(address(_destVault), 44);
        _destVault.depositUnderlying(44);

        // Stake in Aura.
        (, bytes memory data) =
            AURA_STAKING.call(abi.encodeWithSignature("deposit(uint256,address)", uint256(555), address(_destVault)));

        // Make sure `deposit()` returning correct amount.
        assertEq(abi.decode(data, (uint256)), 555);

        // Recover underlying, check event.
        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(recoveryAddress, 555);
        _destVault.recoverUnderlying(recoveryAddress);

        // Ensure that amount staked through DV is still present.
        (bool success, bytes memory data2) =
            AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(_destVault)));
        assertEq(success, true);
        assertEq(abi.decode(data2, (uint256)), 44);

        // Make sure underlyer made its way to recoveryAddress.
        assertEq(_underlyer.balanceOf(recoveryAddress), 555);
    }

    function test_recoverUnderlying_RunsProperly_RecoverInternalAndExternal() external {
        address recoveryAddress = vm.addr(1);
        uint256 internalBalance = 444;
        uint256 externalbalance = 555;

        // Give contract TOKEN_RECOVERY_MANAGER.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

        // Transfer tokens to this contract.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);
        _underlyer.transfer(address(_destVault), internalBalance);

        // Approve Aura to take tokens.
        _underlyer.approve(AURA_STAKING, 1000);

        // Stake in Aura.
        // solhint-disable max-line-length
        (, bytes memory data) =
            AURA_STAKING.call(abi.encodeWithSignature("deposit(uint256,address)", externalbalance, address(_destVault)));
        // solhint-enable max-line-length

        // Make sure `deposit()` returning correct amount.
        assertEq(abi.decode(data, (uint256)), externalbalance);

        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(recoveryAddress, externalbalance + internalBalance);
        _destVault.recoverUnderlying(recoveryAddress);

        // Ensure that balanceOf(address(this)) is 0 in Aura.
        (bool success, bytes memory data2) =
            AURA_STAKING.call(abi.encodeWithSignature("balanceOf(address)", address(this)));
        assertEq(success, true);
        assertEq(abi.decode(data2, (uint256)), 0);

        // Make sure underlyer made its way to recoveryAddress.
        assertEq(_underlyer.balanceOf(recoveryAddress), externalbalance + internalBalance);
    }

    function test_DestinationVault_getPool() external {
        assertEq(IDestinationVault(_destVault).getPool(), WSTETH_WETH_GYRO_POOL);
    }

    function test_validateCalculator_EnsuresMatchingUnderlyingWithCalculator() external {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSTETH_WETH_GYRO_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 162
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));

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
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );
    }

    function test_validateCalculator_EnsuresMatchingPoolWithCalculator() external {
        address badPool = makeAddr("badPool");

        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: badPool,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 999
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, address(_underlyer), address(badPool), "pool"
            )
        );
        payable(
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
