/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ISystemRegistry, SystemRegistry } from "src/SystemRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { ILiquidationRow } from "src/interfaces/liquidation/ILiquidationRow.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { StakeTrackingMock } from "test/mocks/StakeTrackingMock.sol";
import { DestinationVaultMainRewarder, MainRewarder } from "src/rewarders/DestinationVaultMainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import {
    ZERO_EX_MAINNET,
    PRANK_ADDRESS,
    CVX_MAINNET,
    WETH_MAINNET,
    TOKE_MAINNET,
    RANDOM,
    ST_ETH_CURVE_LP_TOKEN_MAINNET,
    CURVE_STETH_ETH_WHALE,
    WETH_MAINNET,
    CONVEX_BOOSTER,
    STETH_ETH_CURVE_POOL,
    CURVE_META_REGISTRY_MAINNET,
    LDO_MAINNET,
    CRV_MAINNET
} from "test/utils/Addresses.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

/**
 * @dev This contract represents a mock of the actual AsyncSwapper to be used in tests. It simulates the swapping
 * process by simply minting the target token to the LiquidationRow contract, under the assumption that the swap
 * operation was successful. It doesn't perform any actual swapping of tokens.
 */
contract AsyncSwapperMock is BaseAsyncSwapper {
    MockERC20 private immutable targetToken;
    address private immutable liquidationRow;

    constructor(address _aggregator, MockERC20 _targetToken, address _liquidationRow) BaseAsyncSwapper(_aggregator) {
        targetToken = _targetToken;
        liquidationRow = _liquidationRow;
    }

    function swap(SwapParams memory params) public override returns (uint256 buyTokenAmountReceived) {
        targetToken.mint(liquidationRow, params.buyAmount);
        return params.buyAmount;
    }
}

/**
 * @notice This contract is a wrapper for the LiquidationRow contract.
 * Its purpose is to expose the private functions for testing.
 */
contract LiquidationRowWrapper is LiquidationRow {
    constructor(ISystemRegistry _systemRegistry) LiquidationRow(ISystemRegistry(_systemRegistry)) { }

    function exposed_increaseBalance(address tokenAddress, address vaultAddress, uint256 tokenAmount) public {
        _increaseBalance(tokenAddress, vaultAddress, tokenAmount);
    }
}

contract LiquidationRowTest is Test {
    event SwapperAdded(address indexed swapper);
    event SwapperRemoved(address indexed swapper);
    event BalanceUpdated(address indexed token, address indexed vault, uint256 balance);
    event VaultLiquidated(address indexed vault, address indexed fromToken, address indexed toToken, uint256 amount);
    event GasUsedForVault(address indexed vault, uint256 gasAmount, bytes32 action);
    event FeesTransfered(address indexed receiver, uint256 amountReceived, uint256 fees);

    SystemRegistry internal systemRegistry;
    DestinationVaultRegistry internal destinationVaultRegistry;
    DestinationVaultFactory internal destinationVaultFactory;
    DestinationRegistry internal destinationTemplateRegistry;
    IAccessController internal accessController;
    LiquidationRowWrapper internal liquidationRow;
    AsyncSwapperMock internal asyncSwapper;
    MockERC20 internal targetToken;

    TestDestinationVault internal testVault;
    MainRewarder internal mainRewarder;

    TestERC20 internal rewardToken;
    TestERC20 internal rewardToken2;
    TestERC20 internal rewardToken3;
    TestERC20 internal rewardToken4;
    TestERC20 internal rewardToken5;

    function setUp() public virtual {
        // Initialize the ERC20 tokens that will be used as rewards to be claimed in the tests
        rewardToken = new TestERC20("rewardToken", "rewardToken");
        rewardToken2 = new TestERC20("rewardToken2", "rewardToken2");
        rewardToken3 = new TestERC20("rewardToken3", "rewardToken3");
        rewardToken4 = new TestERC20("rewardToken4", "rewardToken4");
        rewardToken5 = new TestERC20("rewardToken5", "rewardToken5");

        // Mock the target token using MockERC20 contract which allows us to mint tokens
        targetToken = new MockERC20();

        // Set up system registry with initial configuration
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);

        // Set up access control
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        // Set up destination template registry
        destinationTemplateRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destinationTemplateRegistry));

        // Set up destination vault registry and factory
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);
        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        // Set up LiquidationRow
        liquidationRow = new LiquidationRowWrapper(systemRegistry);

        // grant this contract and liquidatorRow contract the LIQUIDATOR_ROLE so they can call the
        // MainRewarder.queueNewRewards function
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(liquidationRow));

        // Set up the main rewarder
        uint256 newRewardRatio = 800;
        uint256 durationInBlock = 10;
        StakeTrackingMock stakeTracker = new StakeTrackingMock();
        systemRegistry.addRewardToken(address(targetToken));
        mainRewarder = MainRewarder(
            new DestinationVaultMainRewarder(
                systemRegistry, address(stakeTracker), address(targetToken), newRewardRatio, durationInBlock, true
            )
        );

        // Set up test vault
        address baseAsset = address(new TestERC20("baseAsset", "baseAsset"));
        address underlyer = address(new TestERC20("underlyer", "underlyer"));
        testVault = new TestDestinationVault(systemRegistry, address(mainRewarder), baseAsset, underlyer);

        // Set up the async swapper mock
        asyncSwapper = new AsyncSwapperMock(vm.addr(100), targetToken, address(liquidationRow));

        vm.label(address(liquidationRow), "liquidationRow");
        vm.label(address(asyncSwapper), "asyncSwapper");
        vm.label(address(RANDOM), "RANDOM");
        vm.label(address(testVault), "testVault");
        vm.label(address(targetToken), "targetToken");
        vm.label(baseAsset, "baseAsset");
        vm.label(underlyer, "underlyer");
        vm.label(address(rewardToken), "rewardToken");
        vm.label(address(rewardToken2), "rewardToken2");
        vm.label(address(rewardToken3), "rewardToken3");
        vm.label(address(rewardToken4), "rewardToken4");
        vm.label(address(rewardToken5), "rewardToken5");
    }

    /**
     * @dev Sets up a simple mock scenario.
     * In this case, we only setup one type of reward token (`rewardToken`) with an amount of 100.
     * This token will be collected by the vault during the liquidation process.
     * This is used for testing basic scenarios where the vault has only one type of reward token.
     */
    function _mockSimpleScenario(address vault) internal {
        _registerVault(vault);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);

        _mockCalls(vault, amounts, tokens);
    }

    /**
     * @dev Sets up a more complex mock scenario.
     * In this case, we setup five different types of reward tokens
     * (`rewardToken`, `rewardToken2`, `rewardToken3`, `rewardToken4`, `rewardToken5`) each with an amount of 100.
     * These tokens will be collected by the vault during the liquidation process.
     * This is used for testing more complex scenarios where the vault has multiple types of reward tokens.
     */
    function _mockComplexScenario(address vault) internal {
        _registerVault(vault);

        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100;
        amounts[1] = 100;
        amounts[2] = 100;
        amounts[3] = 100;
        amounts[4] = 100;

        address[] memory tokens = new address[](5);
        tokens[0] = address(rewardToken);
        tokens[1] = address(rewardToken2);
        tokens[2] = address(rewardToken3);
        tokens[3] = address(rewardToken4);
        tokens[4] = address(rewardToken5);

        _mockCalls(vault, amounts, tokens);
    }

    function _mockSimpleScenarioWithTargetToken(address vault) internal {
        _registerVault(vault);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;

        address[] memory tokens = new address[](2);
        tokens[0] = address(rewardToken);
        tokens[1] = address(targetToken);

        _mockCalls(vault, amounts, tokens);
    }

    /// @dev Mocks the required calls for the claimsVaultRewards calls.
    function _mockCalls(address vault, uint256[] memory amounts, address[] memory tokens) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            // Can't mint to address(0) so we skip it
            if (tokens[i] != address(0)) {
                TestERC20(tokens[i]).mint(address(liquidationRow), amounts[i]);
            }
        }

        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IDestinationVault.collectRewards.selector),
            abi.encode(amounts, tokens)
        );
    }

    /**
     * @dev Registers a given vault with the vault registry.
     * This is a necessary step in some tests setup to ensure that the vault is recognized by the system.
     */
    function _registerVault(address vault) internal {
        vm.prank(address(destinationVaultFactory));
        destinationVaultRegistry.register(address(vault));
    }

    /**
     * @dev Initializes an array with a single test vault.
     * This helper function is useful for tests that require an array of vaults but only one vault is being tested.
     */
    function _initArrayOfOneTestVault() internal view returns (IDestinationVault[] memory vaults) {
        vaults = new IDestinationVault[](1);
        vaults[0] = testVault;
    }
}

contract AddToWhitelist is LiquidationRowTest {
    function test_RevertIf_CallerIsNotLiquidator() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        liquidationRow.addToWhitelist(RANDOM);
    }

    function test_RevertIf_ZeroAddressGiven() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "swapper"));

        liquidationRow.addToWhitelist(address(0));
    }

    function test_RevertIf_AlreadyAdded() public {
        liquidationRow.addToWhitelist(RANDOM);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        liquidationRow.addToWhitelist(RANDOM);
    }

    function test_AddSwapper() public {
        liquidationRow.addToWhitelist(RANDOM);
        bool val = liquidationRow.isWhitelisted(RANDOM);
        assertTrue(val);
    }

    function test_EmitAddedToWhitelistEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SwapperAdded(RANDOM);

        liquidationRow.addToWhitelist(RANDOM);
    }
}

contract RemoveFromWhitelist is LiquidationRowTest {
    function test_RevertIf_CallerIsNotLiquidator() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        liquidationRow.removeFromWhitelist(RANDOM);
    }

    function test_RevertIf_SwapperNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        liquidationRow.removeFromWhitelist(RANDOM);
    }

    function test_RemoveSwapper() public {
        liquidationRow.addToWhitelist(RANDOM);
        bool val = liquidationRow.isWhitelisted(RANDOM);
        assertTrue(val);

        liquidationRow.removeFromWhitelist(RANDOM);
        val = liquidationRow.isWhitelisted(RANDOM);
        assertFalse(val);
    }

    function test_EmitAddedToWhitelistEvent() public {
        liquidationRow.addToWhitelist(RANDOM);

        vm.expectEmit(true, true, true, true);
        emit SwapperRemoved(RANDOM);

        liquidationRow.removeFromWhitelist(RANDOM);
    }
}

contract IsWhitelisted is LiquidationRowTest {
    function test_ReturnTrueIfWalletIsWhitelisted() public {
        liquidationRow.addToWhitelist(RANDOM);
        bool val = liquidationRow.isWhitelisted(RANDOM);
        assertTrue(val);
    }

    function test_ReturnFalseIfWalletIsNotWhitelisted() public {
        bool val = liquidationRow.isWhitelisted(RANDOM);
        assertFalse(val);
    }
}

contract SetFeeAndReceiver is LiquidationRowTest {
    function test_RevertIf_CallerIsNotLiquidator() public {
        address feeReceiver = address(1);
        uint256 feeBps = 5000;

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);
    }

    function test_RevertIf_FeeIsToHigh() public {
        address feeReceiver = address(1);
        uint256 feeBps = 5001;

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.FeeTooHigh.selector));

        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);
    }

    function test_UpdateFeeValues() public {
        address feeReceiver = address(1);
        uint256 feeBps = 5000;

        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        assertTrue(liquidationRow.feeReceiver() == feeReceiver);
        assertTrue(liquidationRow.feeBps() == feeBps);
    }
}

contract ClaimsVaultRewards is LiquidationRowTest {
    // ⬇️ private functions use for the tests ⬇️

    function _mockRewardTokenHasZeroAmount(address vault) internal {
        _registerVault(vault);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);

        _mockCalls(vault, amounts, tokens);
    }

    function _mockRewardTokenHasZeroAddress(address vault) internal {
        _registerVault(vault);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        _mockCalls(vault, amounts, tokens);
    }

    // ⬇️ actual tests ⬇️

    function test_RevertIf_CallerIsNotLiquidator() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_RevertIf_VaultListIsEmpty() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "vaults"));

        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_RevertIf_AtLeastOneVaultIsNotInRegistry() public {
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        vm.expectRevert(abi.encodeWithSelector(Errors.NotRegistered.selector));

        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_DontUpdateBalancesIf_RewardTokenHasAddressZero() public {
        _mockRewardTokenHasZeroAddress(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        liquidationRow.claimsVaultRewards(vaults);

        uint256 totalBalance = liquidationRow.totalBalanceOf(address(rewardToken));
        uint256 balance = liquidationRow.balanceOf(address(rewardToken), address(testVault));

        assertTrue(totalBalance == 0);
        assertTrue(balance == 0);
    }

    function test_DontUpdateBalancesIf_RewardTokenHasZeroAmount() public {
        _mockRewardTokenHasZeroAmount(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        liquidationRow.claimsVaultRewards(vaults);

        uint256 totalBalance = liquidationRow.totalBalanceOf(address(rewardToken));
        uint256 balance = liquidationRow.balanceOf(address(rewardToken), address(testVault));

        assertTrue(totalBalance == 0);
        assertTrue(balance == 0);
    }

    function test_EmitBalanceUpdatedEvent() public {
        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        vm.expectEmit(true, true, true, true);
        emit BalanceUpdated(address(rewardToken), address(testVault), 100);

        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_EmitGasUsedForVaultEvent() public {
        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        vm.expectEmit(true, false, false, false);
        emit GasUsedForVault(address(testVault), 0, bytes32("liquidation"));

        liquidationRow.claimsVaultRewards(vaults);
    }
}

contract _increaseBalance is LiquidationRowTest {
    function test_RevertIf_ProvidedBalanceIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "balance"));

        liquidationRow.exposed_increaseBalance(address(rewardToken), address(testVault), 0);
    }

    function test_RevertIf_RewardTokenBalanceIsLowerThanAmountGiven() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, address(rewardToken)));

        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

        liquidationRow.exposed_increaseBalance(address(rewardToken), address(testVault), 10);
    }

    function test_EmitBalanceUpdatedEvent() public {
        uint256 amount = 10;

        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(amount));

        vm.expectEmit(true, true, true, true);
        emit BalanceUpdated(address(rewardToken), address(testVault), amount);

        liquidationRow.exposed_increaseBalance(address(rewardToken), address(testVault), amount);
    }

    function test_UpdateBalances() public {
        uint256 amount = 10;

        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(amount));

        liquidationRow.exposed_increaseBalance(address(rewardToken), address(testVault), amount);

        uint256 totalBalance = liquidationRow.totalBalanceOf(address(rewardToken));
        uint256 balance = liquidationRow.balanceOf(address(rewardToken), address(testVault));

        assertTrue(totalBalance == amount);
        assertTrue(balance == amount);
    }
}

contract LiquidateVaultsForToken is LiquidationRowTest {
    uint256 private buyAmount = 200; // == amountReceived
    address private feeReceiver = address(1);
    uint256 private feeBps = 5000;
    uint256 private expectedfeesTransfered = buyAmount * feeBps / 10_000;

    function test_RevertIf_CallerIsNotLiquidator() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 200, address(targetToken), 200, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        vm.prank(RANDOM);
        liquidationRow.liquidateVaultsForToken(address(rewardToken), address(1), vaults, swapParams);
    }

    function test_RevertIf_AsyncSwapperIsNotWhitelisted() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 200, address(targetToken), 200, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        liquidationRow.liquidateVaultsForToken(address(rewardToken), address(1), vaults, swapParams);
    }

    function test_RevertIf_AtLeastOneOfTheVaultsHasNoClaimedRewardsYet() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 200, address(targetToken), 200, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));

        liquidationRow.liquidateVaultsForToken(address(rewardToken), address(asyncSwapper), vaults, swapParams);
    }

    function test_RevertIf_BuytokenaddressIsDifferentThanTheVaultRewarderRewardTokenAddress() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 100, address(targetToken), 200, new bytes(0), new bytes(0));

        // pretend that the rewarder is returning a different token than the one we are trying to liquidate
        vm.mockCall(
            address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.rewardToken.selector), abi.encode(address(1))
        );

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.InvalidRewardToken.selector));

        liquidationRow.liquidateVaultsForToken(address(rewardToken), address(asyncSwapper), vaults, swapParams);
    }

    function test_RevertIf_VaultBalanceAndSellAmountMismatch() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 500, address(targetToken), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.SellAmountMismatch.selector, 100, 500));
        liquidationRow.liquidateVaultsForToken(address(rewardToken2), address(asyncSwapper), vaults, swapParams);
    }

    function test_OnlyLiquidateGivenTokenForGivenVaults() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 100, address(targetToken), 100, new bytes(0), new bytes(0));

        liquidationRow.liquidateVaultsForToken(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        assertTrue(liquidationRow.balanceOf(address(rewardToken), address(testVault)) == 100);
        assertTrue(liquidationRow.balanceOf(address(rewardToken2), address(testVault)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken3), address(testVault)) == 100);
        assertTrue(liquidationRow.balanceOf(address(rewardToken4), address(testVault)) == 100);
        assertTrue(liquidationRow.balanceOf(address(rewardToken5), address(testVault)) == 100);

        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken)) == 100);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken2)) == 0);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken3)) == 100);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken4)) == 100);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken5)) == 100);
    }

    function test_AvoidSwapWhenRewardTokenMatchesBaseAsset() public {
        // Tokens are the same, so exchange rate is 1:1.
        uint256 amount = 100;
        SwapParams memory swapParams =
            SwapParams(address(targetToken), amount, address(targetToken), amount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockSimpleScenarioWithTargetToken(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(targetToken).balanceOf(address(mainRewarder));

        liquidationRow.liquidateVaultsForToken(address(targetToken), address(asyncSwapper), vaults, swapParams);

        uint256 balanceAfter = IERC20(targetToken).balanceOf(address(mainRewarder));
        assertTrue(balanceAfter - balanceBefore == amount - 50);
    }

    function test_RevertIf_InvalidSwapParameters() public {
        // Tokens are the same, so exchange rate is 1:1.
        uint256 amount = 100;
        SwapParams memory swapParams =
            SwapParams(address(targetToken), amount, address(targetToken), 2 * amount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockSimpleScenarioWithTargetToken(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.AmountsMismatch.selector, amount, amount * 2));
        liquidationRow.liquidateVaultsForToken(address(targetToken), address(asyncSwapper), vaults, swapParams);
    }

    function test_EmitFeesTransferedEventWhenFeesFeatureIsTurnedOn() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 100, address(targetToken), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectEmit(true, true, true, true);
        emit FeesTransfered(feeReceiver, buyAmount, expectedfeesTransfered);

        liquidationRow.liquidateVaultsForToken(address(rewardToken2), address(asyncSwapper), vaults, swapParams);
    }

    function test_TransferFeesToReceiver() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 100, address(targetToken), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(targetToken).balanceOf(feeReceiver);

        liquidationRow.liquidateVaultsForToken(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        uint256 balanceAfter = IERC20(targetToken).balanceOf(feeReceiver);

        assertTrue(balanceAfter - balanceBefore == expectedfeesTransfered);
    }

    function test_TransferRewardsToMainRewarder() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 100, address(targetToken), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(targetToken).balanceOf(address(mainRewarder));

        liquidationRow.liquidateVaultsForToken(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        uint256 balanceAfter = IERC20(targetToken).balanceOf(address(mainRewarder));

        assertTrue(balanceAfter - balanceBefore == buyAmount - expectedfeesTransfered);
    }
}

/// @dev Contract for integration testing
contract IntegrationTest is LiquidationRowTest {
    CurveConvexDestinationVault private _vault;
    IERC20 private _underlyer;
    IWETH9 private _asset;
    BaseAsyncSwapper private _swapper;

    // Function to set up the test environment
    function setUp() public virtual override {
        // Create a fork for mainnet environment
        uint256 _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 18_043_597);
        vm.selectFork(_mainnetFork);
        super.setUp();

        // Grant CREATE_DESTINATION_VAULT_ROLE to this contract
        accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        // Initialize contract instances
        _underlyer = IERC20(ST_ETH_CURVE_LP_TOKEN_MAINNET);
        _asset = IWETH9(WETH_MAINNET);

        // Add reward token to the system registry
        systemRegistry.addRewardToken(WETH_MAINNET);

        // Initialize CurveConvexDestinationVault parameters
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: STETH_ETH_CURVE_POOL,
            convexStaking: 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
            convexPoolId: 25,
            baseAssetBurnTokenIndex: 0
        });
        bytes memory initParamBytes = abi.encode(initParams);

        // Create CurveConvexDestinationVault template
        CurveConvexDestinationVault dvTemplate =
            new CurveConvexDestinationVault(systemRegistry, CVX_MAINNET, CONVEX_BOOSTER);
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = keccak256(abi.encode("template"));
        destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        destinationTemplateRegistry.register(dvTypes, dvAddresses);

        // Set Curve resolver and create new destination vault
        CurveResolverMainnet curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        systemRegistry.setCurveResolver(address(curveResolver));
        address payable newVault = payable(
            destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                new address[](0), // additionalTrackedTokens
                keccak256("salt1"),
                initParamBytes
            )
        );

        // Set _vault variable to the newly created CurveConvexDestinationVault
        _vault = CurveConvexDestinationVault(newVault);

        // Create a new instance of BaseAsyncSwapper and add it to liquidationRow whitelist
        _swapper = new BaseAsyncSwapper(ZERO_EX_MAINNET);
        liquidationRow.addToWhitelist(address(_swapper));
    }

    /**
     * @dev This test covers the following scenarios:
     * (1) Claim rewards for vaults:
     *   - LiquidationRow.claimsVaultRewards(vaults)
     *
     * (2) Liquidate CVX from vaults to WETH and add it as a reward to Vault.mainRewarder:
     *   - LiquidationRow.liquidateVaultsForToken
     *     - DestinationVault.collectRewards()
     *     - BaseAsyncSwapper.swap()
     *     - DestinationVault.mainRewarder.queueNewRewards()
     */
    function test_IntegrationWorks() public {
        // Initialize ERC20 instances for tokens
        IERC20 cvx = IERC20(CVX_MAINNET);

        // Transfer some tokens to the contract for testing
        vm.prank(0x1C3CB7e3920C77EBA162Cf044F418a854C12fFEf);
        _underlyer.transfer(address(this), 200e18);

        // Mock the Vault Registry and grant deposit rights
        address lmpVaultRegistry = vm.addr(10_000);
        vm.mockCall(
            address(systemRegistry),
            abi.encodeWithSelector(ISystemRegistry.lmpVaultRegistry.selector),
            abi.encode(lmpVaultRegistry)
        );
        vm.mockCall(
            address(lmpVaultRegistry), abi.encodeWithSelector(ILMPVaultRegistry.isVault.selector), abi.encode(true)
        );

        // Deposit tokens into the vault
        _underlyer.approve(address(_vault), 100e18);
        _vault.depositUnderlying(100e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        // Grant LIQUIDATOR_ROLE to this contract
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));

        // Prepare vaults array and claim rewards from the vault
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        vaults[0] = _vault;
        liquidationRow.claimsVaultRewards(vaults);

        // Check CVX balance // 503687657840562
        uint256 cvxBalance = liquidationRow.totalBalanceOf(address(cvx));

        // solhint-disable max-line-length
        // Prepare data for token swap
        // `data` come from the following query at block 18_043_597:
        // https://api.0x.org/swap/v1/quote?sellToken=0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b&buyToken=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2&sellAmount=503687657840562
        bytes memory data =
            hex"6af479b200000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000001ca19ebec5fb200000000000000000000000000000000000000000000000000000196c07c6ad0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000007e318bba9ae117b36f9c30ef2fbefdc8";

        // Expected reward amount based on data above
        uint256 expectedRewards = 1_762_864_930_259;

        // Prepare swap parameters
        SwapParams memory swapParams =
            SwapParams(address(cvx), cvxBalance, WETH_MAINNET, expectedRewards, data, new bytes(0));

        // Perform token swap
        liquidationRow.liquidateVaultsForToken(address(cvx), address(_swapper), vaults, swapParams);

        uint256 rewards = MainRewarder(_vault.rewarder()).currentRewards();

        // Assert that liquidated amount has been added to rewarder
        assertTrue(expectedRewards == rewards);
    }
}
