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
import { WETH_MAINNET, TOKE_MAINNET, RANDOM } from "test/utils/Addresses.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
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

    TestIncentiveCalculator internal testIncentiveCalculator;
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
        testIncentiveCalculator = new TestIncentiveCalculator(underlyer);
        testVault = new TestDestinationVault(
            systemRegistry, address(mainRewarder), baseAsset, underlyer, address(testIncentiveCalculator)
        );

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
