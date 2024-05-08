// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault, IDestinationVault } from "src/vault/DestinationVault.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import {
    WETH_MAINNET,
    BAL_VAULT,
    WSTETH_MAINNET,
    WSTETH_WETH_GYRO_POOL,
    GYRO_WSTETH_WETH_WHALE
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

///@notice We use BalancerDestinationVault contract to interact with Gyroscope.
contract BalancerGyroscopeDestinationVaultTests is Test {
    address private constant POOL_ADDRESS = WSTETH_WETH_GYRO_POOL;
    address private constant LP_TOKEN_WHALE = GYRO_WSTETH_WETH_WHALE; // ~0.21

    uint256 private _mainnetFork;

    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    DestinationVaultFactory private _destinationVaultFactory;
    DestinationVaultRegistry private _destinationVaultRegistry;
    DestinationRegistry private _destinationTemplateRegistry;

    IAutopoolRegistry private _autopoolRegistry;
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
        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_661_436);
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
            pool: POOL_ADDRESS,
            swapper: balSwapper,
            data: abi.encode(0xf01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005de) // wstETH/WETH pool id
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

        _underlyer = IERC20(POOL_ADDRESS);
        vm.label(address(_underlyer), "underlyer");

        BalancerDestinationVault dvTemplate = new BalancerDestinationVault(_systemRegistry, BAL_VAULT);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: POOL_ADDRESS });
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

        // Set Autopool registry for permissions
        _autopoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autopoolRegistry), "autopoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autopoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autopoolRegistry));
    }

    function test_initializer_ConfiguresVault() public {
        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: POOL_ADDRESS });
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

    function test_underlyingTokens() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20Metadata(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20Metadata(tokens[1]).symbol(), "WETH");
    }

    function test_depositUnderlying_TokensStayInDestinationVault() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 0.1e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 0.1e18);
        _destVault.depositUnderlying(0.1e18);

        // Ensure the funds are present internally
        assertEq(_destVault.internalDebtBalance(), 0.1e18);
        assertEq(_underlyer.balanceOf(address(_destVault)), 0.1e18);
    }

    function test_collectRewards_ReturnsNoTokensAndAmounts() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 0.1e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 0.1e18);
        _destVault.depositUnderlying(0.1e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 0);
    }

    function test_withdrawUnderlying() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 0.1e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 0.1e18);
        _destVault.depositUnderlying(0.1e18);

        // Ensure the funds went to vault
        assertEq(_destVault.internalQueriedBalance(), 0.1e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(0.1e18, receiver);

        assertEq(received, 0.1e18);
        assertEq(_underlyer.balanceOf(receiver), 0.1e18);
        assertEq(_destVault.internalDebtBalance(), 0e18);
        assertEq(_destVault.externalDebtBalance(), 0e18);
    }

    function test_withdrawBaseAsset_ReturnsAppropriateAmount() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 0.2e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 0.2e18);
        _destVault.depositUnderlying(0.2e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        uint256 received = _destVault.withdrawBaseAsset(0.01e18, receiver);

        // Gyro pool has a rough pool value of $6,152,143
        // Total Supply of 1897770448632704828929
        // Eth Price: $3190
        // PPS: 1.0117177497526466 w/0.1 shares ~= 0.110117177497526466

        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_117_177_497_526_466);
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

        // Give contract TOKEN_RECOVERY_MANAGER.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

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

        // Give contract TOKEN_RECOVERY_MANAGER.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, address(this));

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
        assertEq(IDestinationVault(_destVault).getPool(), POOL_ADDRESS);
    }

    function test_validateCalculator_EnsuresMatchingUnderlyingWithCalculator() external {
        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: POOL_ADDRESS });
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

        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: badPool });

        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
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
            address(_autopoolRegistry),
            abi.encodeWithSelector(IAutopoolRegistry.isVault.selector, vault),
            abi.encode(isVault)
        );
    }
}
