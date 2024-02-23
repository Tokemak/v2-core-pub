// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault, IDestinationVault } from "src/vault/DestinationVault.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import {
    WETH_MAINNET,
    WSETH_WETH_BAL_POOL,
    STETH_MAINNET,
    BAL_VAULT,
    BAL_MAINNET,
    WSTETH_MAINNET,
    BAL_WSTETH_WETH_WHALE
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract BalancerDestinationVaultTests is Test {
    address private constant LP_TOKEN_WHALE = BAL_WSTETH_WETH_WHALE; //~20

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

    BalancerDestinationVault private _destVault;

    SwapRouter private swapRouter;
    BalancerV2Swap private balSwapper;

    address[] private additionalTrackedTokens;

    event UnderlyerRecovered(address destination, uint256 amount);

    function setUp() public {
        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_586_885);
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
        wstethSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: WSETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080) // wstETH/WETH pool
         });
        swapRouter.setSwapRoute(WSTETH_MAINNET, wstethSwapRoute);
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

        _underlyer = IERC20(WSETH_WETH_BAL_POOL);
        vm.label(address(_underlyer), "underlyer");

        BalancerDestinationVault dvTemplate = new BalancerDestinationVault(_systemRegistry, BAL_VAULT);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: WSETH_WETH_BAL_POOL });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));
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

        _destVault = BalancerDestinationVault(newVault);

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
    }

    function test_initializer_ConfiguresVault() public {
        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: WSETH_WETH_BAL_POOL });
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

    function test_underlyingTokens_ReturnsForMetastable() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20Metadata(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20Metadata(tokens[1]).symbol(), "WETH");
    }

    function test_depositUnderlying_TokensStayInDestinationVault() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds are present internally
        assertEq(_destVault.internalDebtBalance(), 10e18);
        assertEq(_underlyer.balanceOf(address(_destVault)), 10e18);
    }

    function test_collectRewards_ReturnsNoTokensAndAmounts() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        _accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 0);
    }

    function test_withdrawUnderlying() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to vault
        assertEq(_destVault.internalQueriedBalance(), 10e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(10e18, receiver);

        assertEq(received, 10e18);
        assertEq(_underlyer.balanceOf(receiver), 10e18);
        assertEq(_destVault.internalDebtBalance(), 0e18);
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

        // Bal pool has a rough pool value of $96,362,068
        // Total Supply of 50180.410952857663703844
        // Eth Price: $1855
        // PPS: 1.035208869 w/10 shares ~= 10.35208869

        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_356_898_854_512_073_834);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    /// @dev Based on the same data as test_withdrawBaseAsset_ReturnsAppropriateAmount
    function test_estimateWithdrawBaseAsset_ReturnsAppropriateAmount() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);

        uint256 beforeBalance = _asset.balanceOf(receiver);
        uint256 received = _destVault.estimateWithdrawBaseAsset(10e18, receiver, address(0));
        uint256 afterBalance = _asset.balanceOf(receiver);

        // Bal pool has a rough pool value of $96,362,068
        // Total Supply of 50180.410952857663703844
        // Eth Price: $1855
        // PPS: 1.035208869 w/10 shares ~= 10.35208869

        assertEq(received, 10_356_898_854_512_073_834);
        assertEq(beforeBalance, afterBalance);
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
        assertEq(_destVault.internalDebtBalance(), localDepositAmount);
        assertEq(_destVault.externalDebtBalance(), 0);

        _destVault.withdrawUnderlying(localWithdrawalAmount, address(this));

        // Check balances after withdrawing underlyer.
        assertEq(_destVault.internalDebtBalance(), localDepositAmount - localWithdrawalAmount);
        assertEq(_destVault.externalDebtBalance(), 0);
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

    function test_InternalQueriedBalance_CapturesUnderlyerInVault() external {
        // Transfer tokens to address.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        assertEq(_destVault.internalQueriedBalance(), 1000);
    }

    /**
     * Below three functions test `DestinationVault.recoverUnderlying()`.  When there is an excess externally staked
     *      balance, this function interacts with the  protocol that the underlyer is staked into, making it easier
     *      to test here with a full working DV rather than the TestDestinationVault contract in
     *      `DestinationVault.t.sol`.
     */
    function test_recoverUnderlying_RunsProperly_RecoverInternal() external {
        address recoveryAddress = vm.addr(1);

        // Give contract TOKEN_RECOVERY_ROLE.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_ROLE, address(this));

        // Transfer tokens to this contract.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer LP in vault.
        _underlyer.transfer(address(_destVault), 555);

        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(recoveryAddress, 555);
        _destVault.recoverUnderlying(recoveryAddress);

        // Make sure underlyer made its way to recoveryAddress.
        assertEq(_underlyer.balanceOf(recoveryAddress), 555);
    }

    // Tests to make sure that excess external debt is being calculated properly.
    function test_recoverUnderlying_RunsProperly_ExternalDebt() external {
        address recoveryAddress = vm.addr(1);

        // Give contract TOKEN_RECOVERY_ROLE.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_ROLE, address(this));

        // Transfer tokens to this contract.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 2000);

        // Deposit underlying through DV.
        _mockIsVault(address(this), true);
        _underlyer.approve(address(_destVault), 44);
        _destVault.depositUnderlying(44);

        // Transfer LP to Vault
        _underlyer.transfer(address(_destVault), 555);

        // Recover underlying, check event.
        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(recoveryAddress, 555);
        _destVault.recoverUnderlying(recoveryAddress);

        // Ensure that amount staked through DV is still present.
        assertEq(_underlyer.balanceOf(address(_destVault)), 44);

        // Make sure underlyer made its way to recoveryAddress.
        assertEq(_underlyer.balanceOf(recoveryAddress), 555);
    }

    function test_DestinationVault_getPool() external {
        assertEq(IDestinationVault(_destVault).getPool(), WSETH_WETH_BAL_POOL);
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
