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
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import {
    WETH_MAINNET,
    WSETH_WETH_BAL_POOL,
    STETH_MAINNET,
    BAL_VAULT,
    BAL_MAINNET,
    AURA_BOOSTER,
    WSTETH_MAINNET,
    AURA_MAINNET,
    BAL_WSTETH_WETH_WHALE
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract BalancerAuraDestinationVaultTests is Test {
    address private constant LP_TOKEN_WHALE = BAL_WSTETH_WETH_WHALE; //~20
    address private constant AURA_STAKING = 0x59D66C58E83A26d6a0E35114323f65c3945c89c1;

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
            balancerPool: WSETH_WETH_BAL_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 115
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
    }

    function test_initializer_ConfiguresVault() public {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: WSETH_WETH_BAL_POOL,
            auraStaking: AURA_STAKING,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 115
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

    function test_underlyingTokens_ReturnsForMetastable() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20Metadata(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20Metadata(tokens[1]).symbol(), "WETH");
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
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

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
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

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

        IERC20 bal = IERC20(BAL_MAINNET);
        IERC20 aura = IERC20(AURA_MAINNET);

        _accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));

        uint256 preBalBAL = bal.balanceOf(address(this));
        uint256 preBalAURA = aura.balanceOf(address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 3);
        assertEq(address(tokens[0]), address(0)); // stash token
        assertEq(address(tokens[1]), BAL_MAINNET);
        assertEq(address(tokens[2]), AURA_MAINNET);

        assertTrue(amounts[1] > 0);
        assertTrue(amounts[2] > 0);

        uint256 afterBalBAL = bal.balanceOf(address(this));
        uint256 afterBalAURA = aura.balanceOf(address(this));

        assertEq(amounts[1], afterBalBAL - preBalBAL);
        assertEq(amounts[2], afterBalAURA - preBalAURA);
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
        assertEq(_destVault.externalQueriedBalance(), 10e18);

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

        // Give contract TOKEN_RECOVERY_ROLE.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_ROLE, address(this));

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

        // Give contract TOKEN_RECOVERY_ROLE.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_ROLE, address(this));

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

        // Give contract TOKEN_RECOVERY_ROLE.
        _accessController.setupRole(Roles.TOKEN_RECOVERY_ROLE, address(this));

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
