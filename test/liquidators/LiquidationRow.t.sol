// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-states-count,max-line-length */

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ISystemRegistry, SystemRegistry } from "src/SystemRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { ILiquidationRow } from "src/interfaces/liquidation/ILiquidationRow.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { WETH_MAINNET, TOKE_MAINNET, RANDOM } from "test/utils/Addresses.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";

/**
 * @dev This contract represents a mock of the actual AsyncSwapper to be used in tests. It simulates the swapping
 * process by simply minting the buyTokenAddress token to the LiquidationRow contract, under the assumption that the
 * swap
 * operation was successful. It doesn't perform any actual swapping of tokens.
 */
contract AsyncSwapperMock is BaseAsyncSwapper {
    address private immutable liquidationRow;

    constructor(address _aggregator, address _liquidationRow) BaseAsyncSwapper(_aggregator) {
        liquidationRow = _liquidationRow;
    }

    function swap(SwapParams memory params) public override returns (uint256 buyTokenAmountReceived) {
        TestERC20(params.buyTokenAddress).mint(liquidationRow, params.buyAmount);
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
    event FeesTransferred(address indexed receiver, uint256 amountReceived, uint256 fees);

    SystemRegistry internal systemRegistry;
    DestinationVaultRegistry internal destinationVaultRegistry;
    DestinationVaultFactory internal destinationVaultFactory;
    DestinationRegistry internal destinationTemplateRegistry;
    IAccessController internal accessController;
    LiquidationRowWrapper internal liquidationRow;
    AsyncSwapperMock internal asyncSwapper;

    address internal baseAsset;
    address internal underlyer;

    TestIncentiveCalculator internal testIncentiveCalculator;
    TestDestinationVault internal testVault;
    TestDestinationVault internal testVault2;

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

        // Set up system registry with initial configuration
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);

        // Set up access control
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        // Set up Destination Template Registry
        bytes32 dvType = keccak256(abi.encode("test"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;

        TestDestinationVault dv = new TestDestinationVault(systemRegistry);
        address[] memory dvs = new address[](1);
        dvs[0] = address(dv);

        destinationTemplateRegistry = new DestinationRegistry(systemRegistry);
        destinationTemplateRegistry.addToWhitelist(dvTypes);
        destinationTemplateRegistry.register(dvTypes, dvs);
        systemRegistry.setDestinationTemplateRegistry(address(destinationTemplateRegistry));

        // Set up Destination Vault Registry
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        // Set up Destination Vault Factory
        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);
        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        // Set up LiquidationRow
        liquidationRow = new LiquidationRowWrapper(systemRegistry);

        // grant this contract and liquidatorRow contract the LIQUIDATOR_ROLE so they can call the
        // MainRewarder.queueNewRewards function
        accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, address(this));
        accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, address(this));
        accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(liquidationRow));

        // Set up test vault
        baseAsset = address(new TestERC20("baseAsset", "baseAsset"));
        underlyer = address(new TestERC20("underlyer", "underlyer"));

        systemRegistry.addRewardToken(baseAsset);
        systemRegistry.addRewardToken(underlyer);

        testIncentiveCalculator = new TestIncentiveCalculator();
        testIncentiveCalculator.setLpToken(underlyer);

        testVault = TestDestinationVault(
            destinationVaultFactory.create(
                "test",
                baseAsset,
                underlyer,
                address(testIncentiveCalculator),
                new address[](0),
                keccak256("salt1"),
                abi.encode("")
            )
        );

        testVault2 = TestDestinationVault(
            destinationVaultFactory.create(
                "test",
                baseAsset,
                underlyer,
                address(testIncentiveCalculator),
                new address[](0),
                keccak256("salt2"),
                abi.encode("")
            )
        );

        // Set up the async swapper mock
        asyncSwapper = new AsyncSwapperMock(vm.addr(100), address(liquidationRow));

        vm.label(address(liquidationRow), "liquidationRow");
        vm.label(address(asyncSwapper), "asyncSwapper");
        vm.label(address(RANDOM), "RANDOM");
        vm.label(address(testVault), "testVault");
        vm.label(address(baseAsset), "baseAsset");
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
     * In this case, we only setup one type of reward token (`rewardToken`) with an amount of 100_000.
     * This token will be collected by the vault during the liquidation process.
     * This is used for testing basic scenarios where the vault has only one type of reward token.
     */
    function _mockSimpleScenario(address vault) internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100_000;

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);

        _mockCollectRewardsCalls(vault, amounts, tokens);
    }

    /**
     * @dev Sets up a more complex mock scenario.
     * In this case, we setup five different types of reward tokens
     * (`rewardToken`, `rewardToken2`, `rewardToken3`, `rewardToken4`, `rewardToken5`) each with an amount of 100000.
     * These tokens will be collected by the vault during the liquidation process.
     * This is used for testing more complex scenarios where the vault has multiple types of reward tokens.
     */
    function _mockComplexScenario(address vault) internal {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100_000;
        amounts[1] = 100_000;
        amounts[2] = 100_000;
        amounts[3] = 100_000;
        amounts[4] = 100_000;

        address[] memory tokens = new address[](5);
        tokens[0] = address(rewardToken);
        tokens[1] = address(rewardToken2);
        tokens[2] = address(rewardToken3);
        tokens[3] = address(rewardToken4);
        tokens[4] = address(rewardToken5);

        _mockCollectRewardsCalls(vault, amounts, tokens);
    }

    function _mockSimpleScenarioWithTargetToken(address vault) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100_000;
        amounts[1] = 100_000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(rewardToken);
        tokens[1] = address(baseAsset);

        _mockCollectRewardsCalls(vault, amounts, tokens);
    }

    /// @dev Mocks the required calls for the claimsVaultRewards calls.
    function _mockCollectRewardsCalls(address vault, uint256[] memory amounts, address[] memory tokens) internal {
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
     * @dev Initializes an array with a single test vault.
     * This helper function is useful for tests that require an array of vaults but only one vault is being tested.
     */
    function _initArrayOfOneTestVault() internal view returns (IDestinationVault[] memory vaults) {
        vaults = new IDestinationVault[](1);
        vaults[0] = testVault;
    }
}

contract AddToWhitelist is LiquidationRowTest {
    function test_RevertIf_CallerIsNotLiquidationManager() public {
        address swapper = address(1);

        assertEq(liquidationRow.isWhitelisted(swapper), false, "stage1");

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.addToWhitelist(swapper);

        assertEq(liquidationRow.isWhitelisted(swapper), false, "stage2");

        accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.addToWhitelist(swapper);

        assertEq(liquidationRow.isWhitelisted(swapper), true, "stage3");
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
    function test_RevertIf_CallerIsNotLiquidationManager() public {
        address swapper = address(1);

        liquidationRow.addToWhitelist(swapper);
        assertEq(liquidationRow.isWhitelisted(swapper), true, "reg");

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.removeFromWhitelist(swapper);

        accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.removeFromWhitelist(swapper);

        assertEq(liquidationRow.isWhitelisted(swapper), false, "notreg");
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
    function test_RevertIf_CallerIsNotLiquidationManager() public {
        address feeReceiver = address(1);
        uint256 feeBps = 5000;

        assertEq(liquidationRow.feeBps(), 0, "startingFee");
        assertEq(liquidationRow.feeReceiver(), address(0), "startingReceiver");

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        assertEq(liquidationRow.feeBps(), 0, "confirmStartingFee");
        assertEq(liquidationRow.feeReceiver(), address(0), "confirmStartingReceiver");

        accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        assertEq(liquidationRow.feeBps(), feeBps, "endingStartingFee");
        assertEq(liquidationRow.feeReceiver(), feeReceiver, "endingStartingReceiver");
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
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);

        _mockCollectRewardsCalls(vault, amounts, tokens);
    }

    function _mockRewardTokenHasZeroAddress(address vault) internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100_000;

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        _mockCollectRewardsCalls(vault, amounts, tokens);
    }

    // ⬇️ actual tests ⬇️

    function test_RevertIf_CallerIsNotLiquidationExecutor() public {
        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.claimsVaultRewards(vaults);

        accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_RevertIf_VaultListIsEmpty() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "vaults"));

        liquidationRow.claimsVaultRewards(vaults);
    }

    function test_RevertIf_AtLeastOneVaultIsNotInRegistry() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        vaults[0] = IDestinationVault(makeAddr("FAKE_VAULT"));

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
        emit BalanceUpdated(address(rewardToken), address(testVault), 100_000);

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
    uint256 private buyAmount = 200_000; // == amountReceived
    uint256 private sellAmount = 100_000;
    address private feeReceiver = address(1);
    uint256 private feeBps = 5000;
    uint256 private expectedFeesTransferred = buyAmount * feeBps / 10_000;

    function test_RevertIf_CallerIsNotLiquidationExecutor() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );

        accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_RevertIf_AsyncSwapperIsNotWhitelisted() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 200, address(baseAsset), 200, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken), address(1), vaults, swapParams)
        );
    }

    function test_RevertIf_AtLeastOneOfTheVaultsHasNoClaimedRewardsYet() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), 200, address(baseAsset), 200, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_RevertIf_BuytokenaddressIsDifferentThanTheVaultRewarderRewardTokenAddress() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        // pretend that the rewarder is returning a different token than the one we are trying to liquidate
        vm.mockCall(
            testVault.rewarder(), abi.encodeWithSelector(IBaseRewarder.rewardToken.selector), abi.encode(address(1))
        );

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.InvalidRewardToken.selector));

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_RevertIf_VaultBalanceAndSellAmountMismatch() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount * 2, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();
        _mockComplexScenario(address(testVault));

        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.SellAmountMismatch.selector, sellAmount, sellAmount * 2));
        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_OnlyLiquidateGivenTokenForGivenVaults() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );

        assertTrue(liquidationRow.balanceOf(address(rewardToken), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken2), address(testVault)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken3), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken4), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken5), address(testVault)) == 100_000);

        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken2)) == 0);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken3)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken4)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken5)) == 100_000);
    }

    function test_AvoidSwapWhenRewardTokenMatchesBaseAsset() public {
        // Tokens are the same, so exchange rate is 1:1.
        SwapParams memory swapParams =
            SwapParams(address(baseAsset), sellAmount, address(baseAsset), sellAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();

        _mockSimpleScenarioWithTargetToken(address(testVault));
        address rewarder = testVault.rewarder();

        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(address(rewarder));

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(baseAsset), address(asyncSwapper), vaults, swapParams)
        );

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(address(rewarder));
        assertTrue(balanceAfter - balanceBefore == sellAmount - 50_000);
    }

    function test_RevertIf_InvalidAmountsMismatch() public {
        // Tokens are the same, so exchange rate is 1:1.
        SwapParams memory swapParams =
            SwapParams(address(baseAsset), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();

        _mockSimpleScenarioWithTargetToken(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.AmountsMismatch.selector, sellAmount, buyAmount));
        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(baseAsset), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_EmitFeesTransferredEventWhenFeesFeatureIsTurnedOn() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();

        _mockComplexScenario(address(testVault));

        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        vm.expectEmit(true, true, true, true);
        emit FeesTransferred(feeReceiver, buyAmount, expectedFeesTransferred);

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );
    }

    function test_TransferFeesToReceiver() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(feeReceiver);

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(feeReceiver);

        assertTrue(balanceAfter - balanceBefore == expectedFeesTransferred);
    }

    function test_TransferRewardsToMainRewarder() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        _setWhitelistAndFee();

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(testVault.rewarder());

        liquidationRow.liquidateVaultsForToken(
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams)
        );

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(testVault.rewarder());

        assertTrue(balanceAfter - balanceBefore == buyAmount - expectedFeesTransferred);
    }

    function _setWhitelistAndFee() internal {
        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);
    }
}

contract LiquidateVaultsForTokens is LiquidationRowTest {
    uint256 private sellAmount = 100_000;
    uint256 private buyAmount = 200_000; // == amountReceived
    address private feeReceiver = address(1);
    uint256 private feeBps = 5000;
    uint256 private expectedFeesTransferred = buyAmount * feeBps / 10_000;

    function test_RevertIf_CallerIsNotLiquidationExecutor() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vm.prank(RANDOM);
        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, RANDOM);
        vm.prank(RANDOM);
        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_RevertIf_AsyncSwapperIsNotWhitelisted() public {
        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] = ILiquidationRow.LiquidationParams(address(rewardToken), address(1), vaults, swapParams);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_RevertIf_AtLeastOneOfTheVaultsHasNoClaimedRewardsYet() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        SwapParams memory swapParams =
            SwapParams(address(rewardToken), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken), address(asyncSwapper), vaults, swapParams);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));

        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_RevertIf_BuytokenaddressIsDifferentThanTheVaultRewarderRewardTokenAddress() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockSimpleScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        // pretend that the rewarder is returning a different token than the one we are trying to liquidate
        vm.mockCall(
            testVault.rewarder(), abi.encodeWithSelector(IBaseRewarder.rewardToken.selector), abi.encode(address(1))
        );

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken), address(asyncSwapper), vaults, swapParams);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.InvalidRewardToken.selector));

        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_RevertIf_VaultBalanceAndSellAmountMismatch() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), 500, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.SellAmountMismatch.selector, sellAmount, 500));
        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_LiquidatesMultipleTokens() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));
        _mockComplexScenario(address(testVault));
        _mockComplexScenario(address(testVault2));

        IDestinationVault[] memory vaults = new IDestinationVault[](2);
        vaults[0] = testVault;
        vaults[1] = testVault2;
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams2 = SwapParams(
            address(rewardToken2), sellAmount * 2, address(baseAsset), buyAmount * 2, new bytes(0), new bytes(0)
        );
        SwapParams memory swapParams3 = SwapParams(
            address(rewardToken3), sellAmount * 2, address(baseAsset), buyAmount * 2, new bytes(0), new bytes(0)
        );

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](2);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams2);
        liquidateParams[1] =
            ILiquidationRow.LiquidationParams(address(rewardToken3), address(asyncSwapper), vaults, swapParams3);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        assertTrue(liquidationRow.balanceOf(address(rewardToken), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken2), address(testVault)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken3), address(testVault)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken4), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken5), address(testVault)) == 100_000);

        assertTrue(liquidationRow.balanceOf(address(rewardToken), address(testVault2)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken2), address(testVault2)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken3), address(testVault2)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken4), address(testVault2)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken5), address(testVault2)) == 100_000);

        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken)) == 200_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken2)) == 0);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken3)) == 0);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken4)) == 200_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken5)) == 200_000);
    }

    function test_OnlyLiquidateGivenTokenForGivenVaults() public {
        liquidationRow.addToWhitelist(address(asyncSwapper));

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), sellAmount, new bytes(0), new bytes(0));

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        assertTrue(liquidationRow.balanceOf(address(rewardToken), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken2), address(testVault)) == 0);
        assertTrue(liquidationRow.balanceOf(address(rewardToken3), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken4), address(testVault)) == 100_000);
        assertTrue(liquidationRow.balanceOf(address(rewardToken5), address(testVault)) == 100_000);

        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken2)) == 0);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken3)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken4)) == 100_000);
        assertTrue(liquidationRow.totalBalanceOf(address(rewardToken5)) == 100_000);
    }

    function test_AvoidSwapWhenRewardTokenMatchesBaseAsset() public {
        // Tokens are the same, so exchange rate is 1:1.
        SwapParams memory swapParams =
            SwapParams(address(baseAsset), sellAmount, address(baseAsset), sellAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockSimpleScenarioWithTargetToken(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(testVault.rewarder());

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(baseAsset), address(asyncSwapper), vaults, swapParams);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(testVault.rewarder());
        assertTrue(balanceAfter - balanceBefore == sellAmount - 50_000);
    }

    function test_RevertIf_InvalidSwapParameters() public {
        // Tokens are the same, so exchange rate is 1:1.
        SwapParams memory swapParams =
            SwapParams(address(baseAsset), sellAmount, address(baseAsset), 2 * sellAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockSimpleScenarioWithTargetToken(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(baseAsset), address(asyncSwapper), vaults, swapParams);

        vm.expectRevert(abi.encodeWithSelector(ILiquidationRow.AmountsMismatch.selector, sellAmount, sellAmount * 2));
        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_EmitFeesTransferredEventWhenFeesFeatureIsTurnedOn() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        vm.expectEmit(true, true, true, true);
        emit FeesTransferred(feeReceiver, buyAmount, expectedFeesTransferred);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);
    }

    function test_TransferFeesToReceiver() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(feeReceiver);

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(feeReceiver);

        assertTrue(balanceAfter - balanceBefore == expectedFeesTransferred);
    }

    function test_TransferRewardsToMainRewarder() public {
        SwapParams memory swapParams =
            SwapParams(address(rewardToken2), sellAmount, address(baseAsset), buyAmount, new bytes(0), new bytes(0));

        liquidationRow.addToWhitelist(address(asyncSwapper));
        liquidationRow.setFeeAndReceiver(feeReceiver, feeBps);

        _mockComplexScenario(address(testVault));
        IDestinationVault[] memory vaults = _initArrayOfOneTestVault();
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balanceBefore = IERC20(baseAsset).balanceOf(testVault.rewarder());

        ILiquidationRow.LiquidationParams[] memory liquidateParams = new ILiquidationRow.LiquidationParams[](1);
        liquidateParams[0] =
            ILiquidationRow.LiquidationParams(address(rewardToken2), address(asyncSwapper), vaults, swapParams);

        liquidationRow.liquidateVaultsForTokens(liquidateParams);

        uint256 balanceAfter = IERC20(baseAsset).balanceOf(testVault.rewarder());

        assertTrue(balanceAfter - balanceBefore == buyAmount - expectedFeesTransferred);
    }
}
