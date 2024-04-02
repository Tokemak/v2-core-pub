// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count,var-name-mixedcase,no-console

import { Roles } from "src/libs/Roles.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { Errors } from "src/utils/Errors.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { DestinationVaultMocks } from "test/unit/mocks/DestinationVaultMocks.t.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { AutoPoolStrategyMocks } from "test/unit/mocks/AutoPoolStrategyMocks.t.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { SystemSecurityMocks } from "test/unit/mocks/SystemSecurityMocks.t.sol";
import { TestBase } from "test/base/TestBase.sol";
import { StructuredLinkedList } from "src/strategy/StructuredLinkedList.sol";
import { WithdrawalQueue } from "src/strategy/WithdrawalQueue.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { AutoPoolToken } from "src/vault/libs/AutoPoolToken.sol";
import { console } from "forge-std/console.sol";
import { AutoPoolFees } from "src/vault/libs/AutoPoolFees.sol";
import { LMPDestinations } from "src/vault/libs/LMPDestinations.sol";
import { Pausable } from "src/security/Pausable.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { VmSafe } from "forge-std/Vm.sol";

contract LMPVaultTests is
    Test,
    TestBase,
    SystemRegistryMocks,
    SystemSecurityMocks,
    DestinationVaultMocks,
    AccessControllerMocks,
    AutoPoolStrategyMocks
{
    address internal FEE_RECIPIENT = address(4335);

    constructor()
        TestBase(vm)
        SystemRegistryMocks(vm)
        SystemSecurityMocks(vm)
        DestinationVaultMocks(vm)
        AccessControllerMocks(vm)
        AutoPoolStrategyMocks(vm)
    { }

    ISystemRegistry internal systemRegistry;
    IAccessController internal accessController;
    ISystemSecurity internal systemSecurity;
    address internal lmpStrategy;

    TestERC20 internal vaultAsset;

    FeeAndProfitTestVault internal vault;

    struct DVSetup {
        FeeAndProfitTestVault lmpVault;
        uint256 dvSharesToLMP;
        uint256 valuePerShare;
        uint256 minDebtValue;
        uint256 maxDebtValue;
        uint256 lastDebtReportTimestamp;
    }

    /// =====================================================
    /// Events
    /// =====================================================

    event StreamingFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event NewTotalAssetsHighWatermark(uint256 assets, uint256 timestamp);
    event TotalSupplyLimitSet(uint256 limit);
    event PerWalletLimitSet(uint256 limit);
    event SymbolAndDescSet(string symbol, string desc);
    event PeriodicFeeSet(uint256 newFee);
    event PendingPeriodicFeeSet(uint256 pendingPeriodicFeeBps);
    event PeriodicFeeSinkSet(address newPeriodicFeeSink);
    event LastPeriodicFeeTakeSet(uint256 lastPeriodicFeeTake);
    event RebalanceFeeHighWaterMarkEnabledSet(bool enabled);
    event TokensPulled(address[] tokens, uint256[] amounts, address[] destinations);
    event TokensRecovered(address[] tokens, uint256[] amounts, address[] destinations);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event RewarderSet(address rewarder);
    event DestinationDebtReporting(
        address destination, LMPDebt.IdleDebtUpdates debtInfo, uint256 claimed, uint256 claimGasUsed
    );
    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 idle, uint256 debt);
    event PeriodicFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Shutdown(ILMPVault.VaultShutdownStatus reason);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        vm.warp(1_702_419_857);
        systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));

        accessController = IAccessController(makeAddr("accessController"));
        _mockSysRegAccessController(systemRegistry, address(accessController));

        systemSecurity = ISystemSecurity(makeAddr("systemSecurity"));
        _mockSysRegSystemSecurity(systemRegistry, address(systemSecurity));
        _mockSysSecurityInit(systemSecurity);

        vaultAsset = new TestERC20("mockWETH", "Mock WETH");
        vaultAsset.setDecimals(9);
        vm.label(address(vaultAsset), "baseAsset");

        lmpStrategy = makeAddr("lmpStrategy");
        bytes memory initData = abi.encode("");

        _mockNavUpdate(lmpStrategy);

        FeeAndProfitTestVault tempVault = new FeeAndProfitTestVault(systemRegistry, address(vaultAsset));
        vault = FeeAndProfitTestVault(Clones.cloneDeterministic(address(tempVault), "salt1"));
        vault.initialize(lmpStrategy, "1", "1", initData);
        vm.label(address(vault), "FeeAndProfitTestVaultProxy");

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.toggleAllowedUser(address(this));
        vault.toggleAllowedUser(makeAddr("user"));
        vault.toggleAllowedUser(makeAddr("user1"));
        vault.toggleAllowedUser(makeAddr("user2"));
    }

    function test_SetUpState() public {
        assertNotEq(address(systemRegistry), address(0), "setupSystemRegistry");
        assertNotEq(address(accessController), address(0), "setupAccessController");
        assertNotEq(address(vault), address(0), "setupVault");
        assertNotEq(address(vaultAsset), address(0), "setupVaultAsset");

        assertEq(vault.asset(), address(vaultAsset), "asset");
    }

    // ----------------------------------------------
    // Helpers
    // ----------------------------------------------

    function _depositFor(address user, uint256 amount) internal returns (uint256 sharesReceived) {
        vaultAsset.mint(address(this), amount);
        vaultAsset.approve(address(vault), amount);

        if (!vault.allowedUsers(address(this))) {
            vault.toggleAllowedUser(address(this));
        }

        sharesReceived = vault.deposit(amount, user);
    }

    function _mintFor(address user, uint256 assetAmount, uint256 shareAmount) internal returns (uint256 assetsTaken) {
        vaultAsset.mint(address(this), assetAmount);
        vaultAsset.approve(address(vault), assetAmount);
        assetsTaken = vault.mint(shareAmount, user);
    }

    function _createAddDestinationVault(DVSetup memory setup) internal returns (DestinationVaultFake dv) {
        // Create the destination vault
        TestERC20 dvToken = new TestERC20("DV", "DV");
        dvToken.setDecimals(9);
        dv = new DestinationVaultFake(dvToken, TestERC20(setup.lmpVault.asset()));

        // We have our debt reporting snapshot
        setup.lmpVault.setDestinationInfo(
            address(dv),
            (setup.minDebtValue + setup.maxDebtValue) / 2,
            setup.minDebtValue,
            setup.maxDebtValue,
            setup.dvSharesToLMP,
            setup.lastDebtReportTimestamp
        );
    }

    function _setupDestinationVault(DVSetup memory setup) internal returns (DestinationVaultFake dv) {
        dv = _createAddDestinationVault(setup);

        // Set the price that the dv shares are worth.
        // This also affects how much base asset is returned when shares are burned
        dv.setDebtValuePerShare(setup.valuePerShare);
        dv.mint(setup.dvSharesToLMP, address(setup.lmpVault));

        // Act as though we've rebalanced into this destination
        // ------------------------------------------------------------------

        // We should be in the withdrawal queue if we've rebalanced here
        setup.lmpVault.addToWithdrawalQueueTail(address(dv));
        setup.lmpVault.addToDebtReportingTail(address(dv));

        // We have a corresponding total debt value
        vault.increaseTotalDebts((setup.minDebtValue + setup.maxDebtValue) / 2, setup.minDebtValue, setup.maxDebtValue);

        return dv;
    }

    function _mockSucessfulRebalance() internal {
        _mockSucessfulRebalance(lmpStrategy);
    }
}

contract BaseConstructionTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_constructor_UsesBaseAssetDecimals() public {
        assertEq(vault.decimals(), vaultAsset.decimals(), "decimals");
    }

    function test_setFeeSink_RevertIf_CallerMissingFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_FEE_SETTER_ROLE, false);

        address feeSink = makeAddr("feeSink");

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setFeeSink(feeSink);
        vm.stopPrank();

        vault.setFeeSink(feeSink);
    }

    function test_setStreamingFeeBps_RevertIf_CallerMissingFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_FEE_SETTER_ROLE, false);

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setStreamingFeeBps(100);
        vm.stopPrank();

        vault.setStreamingFeeBps(100);
    }

    function test_setPeriodicFeeSink_RevertIf_CallerMissingMgmtFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_PERIODIC_FEE_SETTER_ROLE, false);

        address feeSink = makeAddr("feeSink");

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setPeriodicFeeSink(feeSink);
        vm.stopPrank();

        vault.setPeriodicFeeSink(feeSink);
    }

    function test_setPeriodicFeeBps_RevertIf_CallerMissingMgmtFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_PERIODIC_FEE_SETTER_ROLE, false);

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setPeriodicFeeBps(100);
        vm.stopPrank();

        vault.setPeriodicFeeBps(100);
    }

    function test_setPeriodicFeeBps_RevertIf_FeeIsGreaterThanTenPercent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);

        vm.expectRevert(abi.encodeWithSelector(AutoPoolFees.InvalidFee.selector, 1001));
        vault.setPeriodicFeeBps(1001);

        vault.setPeriodicFeeBps(1000);
    }

    function test_setPeriodicFeeSink_SetsAndEmitsAddress() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);

        address runOne = makeAddr("runOne");
        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeSinkSet(runOne);
        vault.setPeriodicFeeSink(runOne);

        assertEq(vault.getFeeSettings().periodicFeeSink, runOne, "setRunOne");

        address runTwo = address(0);
        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeSinkSet(runTwo);
        vault.setPeriodicFeeSink(runTwo);

        assertEq(vault.getFeeSettings().periodicFeeSink, runTwo, "setRunOne");
    }
}

contract DepositTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SharesGoToReceiver() public {
        address user = makeAddr("user1");
        uint256 amount = 9e18;
        uint256 prevBalance = vaultAsset.balanceOf(user);

        vaultAsset.mint(address(this), amount);
        vaultAsset.approve(address(vault), amount);
        uint256 sharesReceived = vault.deposit(amount, user);

        uint256 newBalance = vault.balanceOf(user);

        assertEq(newBalance, prevBalance + sharesReceived);
    }

    function test_EmitsDepositEvent() public {
        address user = makeAddr("user1");

        vaultAsset.mint(address(this), 10e9);
        vaultAsset.approve(address(vault), 10e9);
        vault.deposit(5e9, user);

        vault.setTotalIdle(4e9);

        uint256 shares = vault.convertToShares(5e9);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), user, 5e9, 6.25e9);
        vault.deposit(5e9, user);

        assertEq(shares, 6.25e9, "shares");
    }

    function test_EmitsNavEvent() public {
        address user = makeAddr("user1");

        vaultAsset.mint(address(this), 10e9);
        vaultAsset.approve(address(vault), 10e9);
        vault.deposit(5e9, user);

        vault.setTotalIdle(4e9);

        vm.expectEmit(true, true, true, true);
        emit Nav(9e9, 0, 11.25e9);
        vault.deposit(5e9, user);
    }

    function test_SharesMintedBasedOnMaxTotalAssets() public {
        address user = makeAddr("user1");
        _depositFor(user, 2e18);

        _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 5e18,
                maxDebtValue: 15e18,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        vault.setTotalIdle(0);

        uint256 calculatedShares = vault.convertToShares(1e18, ILMPVault.TotalAssetPurpose.Deposit);
        uint256 withdrawShares = vault.convertToShares(1e18, ILMPVault.TotalAssetPurpose.Withdraw);
        uint256 globalShares = vault.convertToShares(1e18, ILMPVault.TotalAssetPurpose.Global);
        uint256 actualShares = _depositFor(user, 1e18);

        assertEq(actualShares, calculatedShares, "actual");
        assertTrue(withdrawShares > actualShares, "withdraw");
        assertTrue(globalShares > actualShares, "global");
    }

    function test_StaleDestinationIsRepriced() public {
        address user = makeAddr("user1");
        _depositFor(user, 2e18);

        // Mimic a deployment
        DestinationVaultFake destVault = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 9e18,
                maxDebtValue: 11e18,
                lastDebtReportTimestamp: block.timestamp - 2 days // Make the data stale
             })
        );
        vault.setTotalIdle(0);

        // Get the expected shares based on the value at the last deployment
        uint256 calculatedShares = vault.convertToShares(1e18, ILMPVault.TotalAssetPurpose.Deposit);

        // We had a valuePerShare of 1e18 when we deployed, lets value each LP at 5e18
        // This is the idea that when a pool is attacked and skewed to one side we will take the highest priced
        // Token and value all of the reserves at that price, giving the user the worst execution but still letting
        // it go through and relying on their slippage settings
        _mockDestVaultCeilingPrice(address(destVault), 5e18);

        uint256 actualShares = _depositFor(user, 1e18);

        assertTrue(calculatedShares > actualShares, "shares");
    }

    function test_MultipleStaleDestinationsAreRepriced() public {
        address user = makeAddr("user1");
        _depositFor(user, 2e9);

        // Mimic a deployment
        DestinationVaultFake staleDv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 8e9,
                maxDebtValue: 16e9,
                lastDebtReportTimestamp: block.timestamp - 2 days
            })
        );
        DestinationVaultFake staleDv2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 5e9,
                maxDebtValue: 13e9,
                lastDebtReportTimestamp: block.timestamp - 2 days
            })
        );
        _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9e9,
                maxDebtValue: 11e9,
                lastDebtReportTimestamp: block.timestamp - 1
            })
        );
        //vault.setTotalIdle(0);

        // So at this point we should have
        // Idle: 0
        // Debt Value: 30
        // Min Debt Value: 22,  8 + 5 + 9
        // Max Debt Value: 40, 16 + 13 + 11

        assertEq(vault.getAssetBreakdown().totalIdle, 2e9, "idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 31e9, "debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 22e9, "minDebt");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 40e9, "maxDebt");

        // Get the expected shares based on the value at the last deployment
        // We'd use the max debt value on deposit, (40e9 debt + 2 idle), and 2e9 existing shares
        // 1e9 * 2e9 / 42e9 = 47619047
        uint256 calculatedShares = vault.convertToShares(1e9, ILMPVault.TotalAssetPurpose.Deposit);
        assertEq(calculatedShares, 47_619_047);

        // We use the ceiling price during a repricing
        _mockDestVaultCeilingPrice(address(staleDv1), 5e9);
        _mockDestVaultCeilingPrice(address(staleDv2), 5e9);

        // So originally we had
        // DV1 - Shares 10 value 16
        // DV2 - Shares 10 value 13
        // DV3 - Shares 10 value 11

        // Repriced we have
        // DV1 - Shares 10 value 50
        // DV1 - Shares 10 value 50
        // DV3 - Shares 10 value 11
        // So a total assets of 113 (still have 2 in idle)
        // And then new shares of - 1e9 * 2e9 / 113e9 = 17699115

        uint256 actualShares = _depositFor(user, 1e9);
        assertTrue(calculatedShares > actualShares, "shares");
        assertEq(actualShares, 17_699_115, "newShares");
    }

    function test_InitialSharesMintedOneToOne() public {
        vaultAsset.mint(address(this), 1e18);
        vaultAsset.approve(address(vault), 1e18);

        uint256 beforeShares = vault.balanceOf(address(this));
        uint256 beforeAsset = vaultAsset.balanceOf(address(this));
        uint256 shares = vault.deposit(1000, address(this));
        uint256 afterShares = vault.balanceOf(address(this));
        uint256 afterAsset = vaultAsset.balanceOf(address(this));

        assertEq(shares, 1000, "sharesReturned");
        assertEq(beforeAsset - afterAsset, 1000, "assetChange");
        assertEq(afterShares - beforeShares, 1000, "shareChange");
        assertEq(vault.getAssetBreakdown().totalIdle, 1000, "idle");
    }

    function test_DepositsGoToIdle() public {
        vaultAsset.mint(address(this), 1e18);
        vaultAsset.approve(address(vault), 1e18);
        assertEq(vault.getAssetBreakdown().totalIdle, 0, "beforeIdle");
        vault.deposit(1e18, address(this));
        assertEq(vault.getAssetBreakdown().totalIdle, 1e18, "idle");
    }

    function test_RevertIf_NavDecreases() public {
        address user = makeAddr("user1");
        _depositFor(user, 2e18);

        vaultAsset.mint(address(this), 1e18);
        vaultAsset.approve(address(vault), 1e18);

        vault.nextDepositGetsDoubleShares();

        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavDecreased.selector, 10_000, 7500));
        vault.deposit(1e18, user);
    }

    function test_RevertIf_VaultIsShutdown() public {
        vaultAsset.mint(address(this), 1e18);
        vaultAsset.approve(address(vault), 1e18);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 1000, 0));
        vault.deposit(1000, address(this));
    }

    function test_RevertIf_SystemIsMidNavChange() public {
        _mockSysSecurityNavOpsInProgress(systemSecurity, 1);

        vaultAsset.mint(address(this), 1e18);
        vaultAsset.approve(address(vault), 1e18);

        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavOpsInProgress.selector));
        vault.deposit(1000, address(this));

        _mockSysSecurityNavOpsInProgress(systemSecurity, 0);

        vault.deposit(1000, address(this));
    }

    function test_RevertIf_SharesReceivedWouldBeZero() public {
        vaultAsset.mint(address(this), 2e18);
        vaultAsset.approve(address(vault), 2e18);
        vault.deposit(1e18, address(this));

        // Inflate our totalAssets() such that the next tiny deposit will round to 0
        // in the share calculation
        vault.increaseTotalDebts(10_000e18, 10_000e18, 10_000e18);

        // Too small rounded to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "shares"));
        vault.deposit(100, address(this));

        // But a larger amount still goes in
        uint256 shares = vault.deposit(100_000, address(this));
        assertTrue(shares > 0, "shares");
    }

    function test_RevertIf_PausedLocally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        vaultAsset.mint(address(this), 1000);
        vaultAsset.approve(address(vault), 1000);

        vault.pause();

        vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 1000, 0));
        vault.deposit(1000, address(this));

        vault.unpause();

        uint256 shares = vault.deposit(1000, address(this));
        assertEq(shares, 1000, "shares");
    }

    function test_RevertIf_PausedGlobally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        vaultAsset.mint(address(this), 1000);
        vaultAsset.approve(address(vault), 1000);

        _mockSysSecurityIsSystemPaused(systemSecurity, true);

        vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 1000, 0));
        vault.deposit(1000, address(this));

        _mockSysSecurityIsSystemPaused(systemSecurity, false);

        uint256 shares = vault.deposit(1000, address(this));
        assertEq(shares, 1000, "shares");
    }

    // function test_RevertIf_PerWalletLimitIsHit() public {
    //     // Approve 3 then deposit 1
    //     // Set limit to 2 and then try to deposit 2 which would make 3 total
    //     // Set limit to 3
    //     // See that 2 can now be deposited

    //     vaultAsset.mint(address(this), 3e9);
    //     vaultAsset.approve(address(vault), 3e9);
    //     vault.deposit(1e9, address(this));

    //     _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
    //     vault.setPerWalletLimit(2e9);

    //     vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 2e9, 1e9));
    //     vault.deposit(2e9, address(this));

    //     vault.setPerWalletLimit(3e9);
    //     vault.deposit(2e9, address(this));
    // }

    // function test_RevertIf_TotalSupplyLimitIsHit() public {
    //     // Approve 3 then deposit 1
    //     // Set limit to 2 and then try to deposit 2 which would make 3 total
    //     // Set limit to 3
    //     // See that 2 can now be deposited

    //     vaultAsset.mint(address(this), 3e9);
    //     vaultAsset.approve(address(vault), 3e9);
    //     vault.deposit(1e9, address(this));

    //     _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
    //     vault.setTotalSupplyLimit(2e9);

    //     vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 2e9, 1e9));
    //     vault.deposit(2e9, address(this));

    //     vault.setTotalSupplyLimit(3e9);
    //     vault.deposit(2e9, address(this));
    // }

    // function test_RevertIf_TotalSupplyLimitIsSubsequentlyLowered() public {
    //     // Approve 4 then deposit 3
    //     // Set limit to 1 so the user is already over, trying to deposit 1 fails
    //     // Set limit to 4
    //     // See that the new 1 can now be deposited

    //     vaultAsset.mint(address(this), 4e9);
    //     vaultAsset.approve(address(vault), 4e9);
    //     vault.deposit(3e9, address(this));

    //     _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
    //     vault.setTotalSupplyLimit(1e9);

    //     vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 1e9, 0));
    //     vault.deposit(1e9, address(this));

    //     vault.setTotalSupplyLimit(4e9);
    //     vault.deposit(1e9, address(this));
    // }

    // function test_RevertIf_PerWalletLimitIsSubsequentlyLoweredToZero() public {
    //     vaultAsset.mint(address(this), 1000e9);
    //     vaultAsset.approve(address(vault), 1000e9);
    //     vault.deposit(500e9, address(this));

    //     _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
    //     vault.setPerWalletLimit(50e9);

    //     vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 1, 0));
    //     vault.deposit(1, address(this));
    // }

    // function test_RevertIf_WalletLimitIsReachedAndLowerThanTotalSupply() public {
    //     _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
    //     vault.setPerWalletLimit(25e9);
    //     vault.setTotalSupplyLimit(50e9);

    //     vaultAsset.mint(address(this), 1000e9);
    //     vaultAsset.approve(address(vault), 1000e9);

    //     vm.expectRevert(abi.encodeWithSelector(ILMPVault.ERC4626DepositExceedsMax.selector, 40e9, 25e9));
    //     vault.deposit(40e9, address(this));
    // }
}

contract MintTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SharesGoToReceiver() public {
        address user = makeAddr("user1");
        uint256 amount = 9e18;
        uint256 prevBalance = vaultAsset.balanceOf(user);

        vaultAsset.mint(address(this), amount);
        vaultAsset.approve(address(vault), amount);
        uint256 sharesReceived = vault.mint(amount, user);

        uint256 newBalance = vault.balanceOf(user);

        assertEq(newBalance, prevBalance + sharesReceived);
    }

    function test_EmitsDepositEvent() public {
        address user = makeAddr("user1");

        vaultAsset.mint(address(this), 10e9);
        vaultAsset.approve(address(vault), 10e9);
        vault.mint(5e9, user);

        vault.setTotalIdle(4e9);

        uint256 assets = vault.convertToAssets(6.25e9);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), user, 5e9, 6.25e9);
        vault.mint(6.25e9, user);

        assertEq(assets, 5e9, "assets");
    }

    function test_EmitsNavEvent() public {
        address user = makeAddr("user1");

        vaultAsset.mint(address(this), 10e9);
        vaultAsset.approve(address(vault), 10e9);
        vault.mint(5e9, user);

        vault.setTotalIdle(4e9);

        // Going into the mint, total shares is 5, assets is 4
        // If I mint 6.25 shares thats 6.25 * 4 / 5 so assets is 5
        // We set the idle from earlier to 4 so new totalIdle should be 9
        vm.expectEmit(true, true, true, true);
        emit Nav(9e9, 0, 11.25e9);
        vault.mint(6.25e9, user);
    }

    function test_AssetsRequiredBasedOnMaxTotalAssets() public {
        address user = makeAddr("user1");
        _mintFor(user, 2e18, 2e18);

        _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 5e18,
                maxDebtValue: 15e18,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        vault.setTotalIdle(0);

        uint256 calculatedAssets = vault.convertToAssets(1e18, ILMPVault.TotalAssetPurpose.Deposit);
        uint256 withdrawAssets = vault.convertToAssets(1e18, ILMPVault.TotalAssetPurpose.Withdraw);
        uint256 globalAssets = vault.convertToAssets(1e18, ILMPVault.TotalAssetPurpose.Global);
        uint256 actualAssets = _mintFor(user, calculatedAssets, 1e18);

        assertEq(actualAssets, calculatedAssets, "actual");

        // You get less assets during with draw
        assertTrue(withdrawAssets < actualAssets, "withdraw");

        // You get less assets even with our mid point
        assertTrue(globalAssets < actualAssets, "global");
    }

    function test_StaleDestinationIsRepriced() public {
        address user = makeAddr("user1");
        _depositFor(user, 2e18);

        // Mimic a deployment
        DestinationVaultFake destVault = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 9e18,
                maxDebtValue: 11e18,
                lastDebtReportTimestamp: block.timestamp - 2 days // Make the data stale
             })
        );
        vault.setTotalIdle(0);

        // Get the assets required for the shares we want to deposit
        uint256 calculatedAssets = vault.convertToAssets(1e18, ILMPVault.TotalAssetPurpose.Deposit);

        // We had a valuePerShare of 1e18 when we deployed, lets value each LP at 5e18
        // This is the idea that when a pool is attacked and skewed to one side we will take the highest priced
        // Token and value all of the reserves at that price, giving the user the worst execution but still letting
        // it go through and relying on their slippage settings
        _mockDestVaultCeilingPrice(address(destVault), 5e18);

        // Making sure we have enough assets approved with the .max so we don't
        // have allowance issues
        uint256 actualAssets = _mintFor(user, type(uint96).max, 1e18);

        // It will now require more assets than it would have originally
        assertTrue(actualAssets > calculatedAssets, "assets");
    }

    // function test_Loop2() public {
    //     uint256 multi = 10;

    //     address user = makeAddr("user1");
    //     uint256 userInitialDeposit = 1 * multi;
    //     _depositFor(user, userInitialDeposit);

    //     uint256 newIdle = 2 * multi;
    //     vault.setTotalIdle(newIdle);
    //     vaultAsset.mint(address(vault), newIdle);

    //     vm.prank(user);
    //     vault.redeem(userInitialDeposit - 1, user, user);

    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    // }

    // function test_Loop() public {
    //     uint256 multi = 1;

    //     address user = makeAddr("user1");
    //     _depositFor(user, 10 * multi);
    //     vault.setTotalIdle(12_000_000 * multi);
    //     vaultAsset.mint(address(vault), 12_000_000 * multi);

    //     uint256 totalDeposited = 1 * multi;
    //     uint256 totalWithdrawn = 0;

    //     for (uint256 i = 0; i < 60; i++) {
    //         uint256 totalAssets = vault.totalAssets();
    //         _depositFor(user, 2 * totalAssets - 1);
    //         totalDeposited += 2 * totalAssets - 1;
    //         vm.prank(user);
    //         vault.withdraw(1 * multi, user, user);
    //         totalWithdrawn += 1 * multi;
    //     }

    //     console.log("user1 totalDeposited", totalDeposited - totalWithdrawn);

    //     address user2 = newAddr(1002, "user2");
    //     uint256 user2Deposit = 2 * vault.totalAssets() - 1;
    //     _depositFor(user2, user2Deposit);

    //     uint256 user1Bal = vault.balanceOf(user);
    //     vm.prank(user);
    //     uint256 user1Remove = vault.redeem(user1Bal, user, user);
    //     console.log("user1 removed       ", user1Remove);

    //     console.log("user2 totalDeposited", user2Deposit);

    //     uint256 user2Bal = vault.balanceOf(user2);
    //     vm.prank(user2);
    //     uint256 user2Remove = vault.redeem(user2Bal, user2, user2);
    //     console.log("user2 removed       ", user2Remove);

    //     console.log("endingTotalAssets", vault.totalAssets());
    //     console.log("endingBalance", vaultAsset.balanceOf(address(vault)));
    // }

    // TODO: Finish mimicking the Deposit tests
}

contract WithdrawTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_IdleAssetsUsedWhenAvailable() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e9;
        uint256 sharesMinted = _depositFor(user, depositAmount);

        assertEq(vault.getAssetBreakdown().totalIdle, depositAmount);
        assertEq(vault.getAssetBreakdown().totalDebt, 0);

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(9e9, user, user);

        assertEq(vault.totalIdle(), 0, "idle");
        assertEq(sharesMinted, sharesBurned, "shared");
    }

    function test_IdleAssetsUsedWhenAvailablePartial() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 withdrawAmount = 5e18;
        _depositFor(user, depositAmount);

        assertEq(vault.totalIdle(), depositAmount);
        assertEq(vault.totalDebt(), 0);

        vm.prank(user);
        vault.withdraw(withdrawAmount, user, user);

        assertEq(vault.totalIdle(), depositAmount - withdrawAmount);
    }

    function test_PullsFromWithdrawalQueueSimpleOneToOne() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(0.1e9);

        // Max we could get is the min debt value @ 9.99 but we're going to get .1 slippage
        // so anything higher would revert. For those 9.89 assets we'd burn 9.89 * 10 / 9.99 == 9.8998999
        // shares. Those shares are actually worth 1:1 with slippage, we get 9.7998999 assets
        // That leaves us with ~.090100101 to pull. Given the exchange rate we got on the last round we
        // know that our remaining shares .100100101 are worth .099079868 assets. With that
        // 90100101 / 99079868 is about 90% of what we need so of those remaining shares, we'd burn .091027868
        // 91027868 shares and get 91027868 (no slippage this round). That means we cover our request
        // and have a 927767 overage so that should go into idle.

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(9.89e9, user, user);

        // They were worth 10 but we experienced .1 slippage
        assertEq(sharesBurned, 9_990_927_769, "sharesBurned");

        // We should have cleared everything since we burned all shares
        assertEq(vault.totalIdle(), 927_767, "totalIdle");
        assertEq(vault.totalDebt(), 9_072_233, "totalDebt");
        assertEq(vault.totalDebtMin(), 9_063_159, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 9_081_305, "totalDebtMax");
    }

    function test_PartiallyDecreasesDebtNumbers() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(0.1e9);

        vm.prank(user);
        vault.withdraw(9.99e9 / 2, user, user);

        // With negative slippage we run withdrawals a few times and over pull a bit
        // So we drop a couple into idle
        assertEq(vault.totalIdle(), 1_957_573, "totalIdle");

        assertEq(vault.totalDebt(), 4_903_042_427, "totalDebt");
        assertEq(vault.totalDebtMin(), 4_898_139_384, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 4_907_945_469, "totalDebtMax");
    }

    function test_PositiveSlippageDropsIntoIdle() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(-1e9);

        vm.prank(user);
        vault.withdraw(9.99e9 / 2, user, user);

        // We received positive slippage, so into idle it goes
        // And minor difference in minDebt and actual .005 goes into idle as well
        assertEq(vault.totalIdle(), 1.005e9, "totalIdle");

        assertEq(vault.totalDebt(), 5e9, "totalDebt");
        assertEq(vault.totalDebtMin(), 4.995e9, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 5.005e9, "totalDebtMax");
    }

    function test_AssetsGoToReceiver() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 amount = 9e18;
        uint256 prevBalance = vaultAsset.balanceOf(user2);
        _depositFor(user1, amount);

        vm.prank(user1);
        vault.withdraw(amount, user2, user1);

        uint256 newBalance = vaultAsset.balanceOf(user2);

        assertEq(amount, newBalance - prevBalance, "newBalance");
    }

    function test_EmitsWithdrawEvent() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        _depositFor(user1, 5e9);

        vault.setTotalIdle(4e9);

        // 3.75 shares = 3 (shares) * 5 (totalSupply) / 4 (totalAssets)
        uint256 shares = vault.convertToShares(3e9);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user1, user2, user1, 3e9, 3.75e9);
        vm.prank(user1);
        vault.withdraw(3e9, user2, user1);

        assertEq(shares, 3.75e9, "shares");
    }

    function test_EmitsNavEvent() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 sharesReceived = _depositFor(user1, 5e9);

        vault.setTotalIdle(4e9);

        // 3.75 shares = 3 (shares) * 5 (totalSupply) / 4 (totalAssets)
        uint256 shares = vault.convertToShares(3e9);

        vm.expectEmit(true, true, true, true);

        emit Nav(1e9, 0, sharesReceived - 3.75e9);
        vm.prank(user1);
        vault.withdraw(3e9, user2, user1);

        assertEq(shares, 3.75e9, "shares");
    }

    function test_SharesBurnedBasedOnMinTotalAssets() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        _depositFor(user1, 2e18);

        // Mimic a deployment
        _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 5e18,
                maxDebtValue: 15e18,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        vault.setTotalIdle(0);

        uint256 snapshotId = vm.snapshot();

        // We try to request more than we have overall, which is the min debt value of dv1, 5e18
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LMPDebt.TooFewAssets.selector, 6e18, 5e18));
        vault.withdraw(6e18, user2, user1);
        vm.revertTo(snapshotId);

        // Pulling the full amount of debt, so all shares burned
        vm.prank(user1);
        uint256 sharesBurned = vault.withdraw(5e18, user2, user1);
        assertEq(sharesBurned, 2e18, "scenario2.sharesBurned");
        assertEq(vaultAsset.balanceOf(user2), 5e18, "scenario2.user2Bal");
        assertEq(vault.balanceOf(user1), 0, "scenario2.user1Shares");
        vm.revertTo(snapshotId);

        // Pulling half of the debt we're owed
        vm.prank(user1);
        sharesBurned = vault.withdraw(2.5e18, user2, user1);
        assertEq(sharesBurned, 1e18, "scenario3.sharesBurned");
        assertEq(vaultAsset.balanceOf(user2), 2.5e18, "scenario3.user2Bal");
        assertEq(vault.balanceOf(user1), 1e18, "scenario3.user1Shares");
    }

    function test_AssetsComeFromIdleOneToOneInitially() public {
        uint256 amount = 100_000;
        address user = makeAddr("user");
        _depositFor(user, amount);

        assertEq(vault.getAssetBreakdown().totalIdle, amount, "beginIdle");

        uint256 beforeShares = vault.balanceOf(user);
        uint256 beforeAssets = vaultAsset.balanceOf(user);

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(amount, user, user);

        uint256 afterShares = vault.balanceOf(user);
        uint256 afterAssets = vaultAsset.balanceOf(user);

        assertEq(amount, sharesBurned, "sharesBurned");
        assertEq(amount, beforeShares - afterShares, "sharesBal");
        assertEq(amount, afterAssets - beforeAssets, "assetBal");
        assertEq(vault.getAssetBreakdown().totalIdle, 0, "newIdle");
    }

    function test_ExhaustedDestinationsAreRemovedFromWithdrawalQueue() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 10e18,
                maxDebtValue: 10e18,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        _depositFor(user, 10e18);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        assertEq(vault.isInWithdrawalQueue(address(dv1)), true);

        vm.prank(user);
        vault.withdraw(10e18, user, user);

        assertEq(vault.isInWithdrawalQueue(address(dv1)), false);
    }

    function test_UserReceivesNoMoreThanCachedValueIfValueIncreases() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        // Deployed 200 assets to DV1
        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 100e9,
                valuePerShare: 2e9,
                minDebtValue: 1.95e9 * 100,
                maxDebtValue: 2.05e9 * 100,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Deployed 800 assets to DV1
        DestinationVaultFake destVault2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        vault.setTotalIdle(0);

        // We want to mimic double the value of DV1 so we'll set
        // some positive slippage on the withdrawBaseAsset so we get back more than we'd expect
        destVault1.setWithdrawBaseAssetSlippage(-50e9);

        destVault2.setWithdrawBaseAssetSlippage(-100e9);

        // We're going to ask for roughly 859.5 assets which is 900 shares currently.
        // 859.5 * 1000 / 955 == 900

        // We think we can get 195 assets from DV1. We'll actually get 250 (200 value and 50 positive slippage) from
        // means we have to get the remaining 609.5 from DV2. The amount we are trying to pull is more than DV1 is worth
        // so we'll exhaust the whole thing. So again, the 250 we get from there. For DV2, we only need to use a
        // portion so we calculate how many shares we should burn based on the min value.
        // Thats a total of 760e18 value over 800 shares so roughly ~641.578 shares
        // Those shares are worth 1:1 plus the 100 positive slippage we get will get ~741.578 ETH.
        // That covers the 609.5 we're trying to get and the difference of ~132 drops into idle

        uint256 idleBefore = vault.totalIdle();
        uint256 assetBalBefore = vaultAsset.balanceOf(user);
        uint256 dv1ShareBalBefore = destVault1.balanceOf(address(vault));
        uint256 dv2ShareBalBefore = destVault2.balanceOf(address(vault));

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(859.5e9, user, user);
        uint256 assetBalAfter = vaultAsset.balanceOf(user);
        uint256 idleAfter = vault.totalIdle();

        assertEq(idleBefore, 0, "idleBefore");

        // Extra assets from dv2 drop into idle
        assertEq(idleAfter, 132.078947368e9, "idleAfter");
        assertEq(sharesBurned, 900e9, "returned");
        assertEq(assetBalAfter - assetBalBefore, 859.5e9, "actual");
        assertEq(dv1ShareBalBefore, 100e9, "dv1ShareBalBefore");
        assertEq(destVault1.balanceOf(address(vault)), 0, "dv1ShareBalAfter");
        assertEq(dv2ShareBalBefore, 800e9, "dv2ShareBalBefore");

        // 800 - ~641.578 shares we burned
        assertEq(destVault2.balanceOf(address(vault)), 158.421052632e9, "dv2ShareBalAfter");
    }

    function test_UserReceivesLessAssetsIfPricesDrops() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        // Deployed 200 assets to DV1
        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 100e9,
                valuePerShare: 2e9,
                minDebtValue: 1.95e9 * 100,
                maxDebtValue: 2.05e9 * 100,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Deployed 800 assets to DV1
        DestinationVaultFake destVault2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Mimicking a price drop through our slippage params
        destVault1.setWithdrawBaseAssetSlippage(50e9);
        destVault2.setWithdrawBaseAssetSlippage(100e9, 101e9);

        // We're calling for 300 assets.

        // We think we can get 195 (its minDebtValue from above) which is less than the total we're trying to pull
        // so we will burn all shares. DV1 has an actual price of 2:1, we have 100 shares, so we'd actually
        // get 200 back. But we have 50 of slippage set. So from DV1 we only get 150 back.

        // Now we start trying to get the remaining 150 from DV2. We have a total of 760e18 value over 800 shares so for
        // trying to get 150 we'll burn ~157.894 shares. They're priced 1:1 but with our 100 slippage we only get
        // 57.894 back. So now we have 207.894.

        // Again, we try DV2 because we still have shares there. Remaining amount is ~92.105. This would normally
        // equate to about ~96.952 shares are current prices but the system is going to try to account for the slippage
        // we received. This ~92.105 is also the amount of slippage we received.
        // We have ~642.1 shares remaining from DV2. We burned ~157.78 shares on the previous round but only received
        // 57.894 back and we apply a 1% buffer on the first round of retry so we only count it as 57.31
        // That's 0.363 assets per share so to get our 92.105 assets thats around ~255.25 shares. Now our test harness
        // is also so dynamic so it still thinks shares are worth 1:1 and we've applied a 101 slippage so we get 154.25
        // assets back.

        // In we've burnt 195 value from dv1
        // 150 value from dv2
        // 242.49 from dv2
        // So 587.49 total min debt value. That's 61.5% of the total value, with 1000 shares, 615.17 shares
        // And on the last pull we were shooting for ~92.105 assets but got ~154.25 assets so ~62.15 should drop into
        // idle.

        vault.setTotalIdle(0);

        uint256 idleBefore = vault.totalIdle();
        uint256 assetBalBefore = vaultAsset.balanceOf(user);
        uint256 dv1ShareBalBefore = destVault1.balanceOf(address(vault));
        uint256 dv2ShareBalBefore = destVault2.balanceOf(address(vault));

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(300e9, user, user);
        uint256 assetBalAfter = vaultAsset.balanceOf(user);
        uint256 idleAfter = vault.totalIdle();

        assertEq(idleBefore, 0, "idleBefore");
        assertEq(idleAfter, 62.151817185e9, "idleAfter");

        assertEq(sharesBurned, 615.177200342e9, "sharesBurned");
        assertEq(assetBalAfter - assetBalBefore, 300e9, "actualAssets");
        assertEq(dv1ShareBalBefore, 100e9, "dv1ShareBalBefore");
        assertEq(destVault1.balanceOf(address(vault)), 0, "dv1ShareBalAfter");
        assertEq(dv2ShareBalBefore, 800e9, "dv2ShareBalBefore");

        // 800 - ~157.78 - ~255.25 shares we burned
        assertEq(destVault2.balanceOf(address(vault)), 386.848182815e9, "dv2ShareBalAfter");
    }

    function test_StaleDestinationIsRepriced() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp - 2 days // Make the data stale
             })
        );

        vault.setTotalIdle(0);

        // Get how many shares we'd expect this to take
        // 1 * 1000 / 760 = ~1.3e9
        uint256 calculatedShares = vault.convertToShares(1e9, ILMPVault.TotalAssetPurpose.Withdraw);

        // We knock the price of our assets nearly in half though
        // 1 * 1000 / 400 (.5 price * 800 shares) = 2.5
        _mockDestVaultFloorPrice(address(destVault1), 0.5e9);

        vm.prank(user);
        uint256 actualShares = vault.withdraw(1e9, user, user);

        assertEq(calculatedShares, 1_315_789_473, "calc");
        assertEq(actualShares, 2.5e9, "actual");
        assertTrue(actualShares > calculatedShares, "shares");
    }

    function test_WithdrawPossibleIfVaultIsShutdown() public {
        address user = makeAddr("user");
        _depositFor(user, 2e9);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(vaultAsset.balanceOf(user), 0, "prevBal");

        vm.prank(user);
        vault.withdraw(1e9, user, user);

        assertEq(vaultAsset.balanceOf(user), 1e9, "newBal");
    }

    // TODO: Change name back
    function test_RevertIf_NavDecreases1() public {
        address user = makeAddr("user");
        _depositFor(user, 2e18);

        vault.setNextWithdrawHalvesIdle();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavDecreased.selector, 10_000, 5000));
        vault.withdraw(1e18, user, user);
        vm.stopPrank();
    }

    function test_RevertIf_SystemIsMidNavChange() public {
        address user = makeAddr("user");
        _depositFor(user, 2e9);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(vaultAsset.balanceOf(user), 0, "prevBal");

        _mockSysSecurityNavOpsInProgress(systemSecurity, 1);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavOpsInProgress.selector));
        vault.withdraw(1e9, user, user);
        vm.stopPrank();

        assertEq(vaultAsset.balanceOf(user), 0, "interimBal");

        _mockSysSecurityNavOpsInProgress(systemSecurity, 0);

        vm.startPrank(user);
        vault.withdraw(1e9, user, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), 1e9, "newBal");
    }

    function test_RevertIf_PausedLocally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        address user = makeAddr("user");
        uint256 shares = _depositFor(user, 2e18);

        vault.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.withdraw(1e18, user, user);
        vm.stopPrank();

        vault.unpause();

        assertEq(vault.balanceOf(user), shares, "shares");
    }

    function test_RevertIf_PausedGlobally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        address user = makeAddr("user");
        uint256 shares = _depositFor(user, 2e18);

        _mockSysSecurityIsSystemPaused(systemSecurity, true);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.withdraw(1e18, user, user);
        vm.stopPrank();

        _mockSysSecurityIsSystemPaused(systemSecurity, false);

        assertEq(vault.balanceOf(user), shares, "shares");
    }
}

contract ShutdownTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetsIsShutdownToTrue() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        assertEq(vault.isShutdown(), false, "before");

        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(vault.isShutdown(), true, "after");
    }

    function test_SetsShutdownStatusToProvidedValue() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        assertEq(uint256(vault.shutdownStatus()), uint256(ILMPVault.VaultShutdownStatus.Active), "before");

        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(uint256(vault.shutdownStatus()), uint256(ILMPVault.VaultShutdownStatus.Deprecated), "after");
    }

    function test_EmitsEventDeprecated() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        emit Shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
    }

    function test_EmitsEventExploit() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        emit Shutdown(ILMPVault.VaultShutdownStatus.Exploit);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Exploit);
    }

    function test_RevertIf_NotCalledByAdmin() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
    }

    function test_RevertIf_TriedToSetToActiveStatus() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        vm.expectRevert(
            abi.encodeWithSelector(ILMPVault.InvalidShutdownStatus.selector, ILMPVault.VaultShutdownStatus.Active)
        );
        vault.shutdown(ILMPVault.VaultShutdownStatus.Active);
    }
}

contract RecoverTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SendsSpecifiedTokenAmountsToDestinations() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address receiverOne = makeAddr("receiverOne");
        address receiverTwo = makeAddr("receiverTwo");

        TestERC20 cToken = new TestERC20("c", "c");
        TestERC20 dToken = new TestERC20("d", "d");
        cToken.mint(address(vault), 5e18);
        dToken.mint(address(vault), 10e18);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        address[] memory destinations = new address[](2);

        tokens[0] = address(cToken);
        tokens[1] = address(dToken);

        amounts[0] = 4e18;
        amounts[1] = 9e18;

        destinations[0] = receiverOne;
        destinations[1] = receiverTwo;

        assertEq(cToken.balanceOf(address(vault)), 5e18, "vaultCBefore");
        assertEq(dToken.balanceOf(address(vault)), 10e18, "vaultDBefore");

        vault.recover(tokens, amounts, destinations);

        assertEq(cToken.balanceOf(address(vault)), 1e18, "vaultCAfter");
        assertEq(dToken.balanceOf(address(vault)), 1e18, "vaultDAfter");

        assertEq(cToken.balanceOf(address(receiverOne)), 4e18, "receiverC");
        assertEq(dToken.balanceOf(address(receiverTwo)), 9e18, "receiverD");
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address receiverOne = makeAddr("receiverOne");
        address receiverTwo = makeAddr("receiverTwo");

        TestERC20 cToken = new TestERC20("c", "c");
        TestERC20 dToken = new TestERC20("d", "d");
        cToken.mint(address(vault), 5e18);
        dToken.mint(address(vault), 10e18);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        address[] memory destinations = new address[](2);

        tokens[0] = address(cToken);
        tokens[1] = address(dToken);

        amounts[0] = 4e18;
        amounts[1] = 9e18;

        destinations[0] = receiverOne;
        destinations[1] = receiverTwo;

        vm.expectEmit(true, true, true, true);
        emit TokensRecovered(tokens, amounts, destinations);
        vault.recover(tokens, amounts, destinations);
    }

    function test_RevertIf_TokenLengthIsZero() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address[] memory zeroAddr = new address[](0);
        uint256[] memory oneNum = new uint256[](1);
        address[] memory oneAddr = new address[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        vault.recover(zeroAddr, oneNum, oneAddr);
    }

    function test_RevertIf_CallerIsNotTokenRecoveryRole() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, false);

        address[] memory oneAddr = new address[](1);
        uint256[] memory oneNum = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.recover(oneAddr, oneNum, oneAddr);
    }

    function test_RevertIf_ArrayLengthMismatch() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address[] memory oneAddr = new address[](1);
        uint256[] memory oneNum = new uint256[](1);
        address[] memory twoAddr = new address[](2);
        uint256[] memory twoNum = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2, "tokens+amounts"));
        vault.recover(oneAddr, twoNum, oneAddr);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 1, "tokens+amounts"));
        vault.recover(twoAddr, oneNum, twoAddr);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2, "tokens+destinations"));
        vault.recover(oneAddr, oneNum, twoAddr);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 1, "tokens+destinations"));
        vault.recover(twoAddr, twoNum, oneAddr);
    }

    // TODO: Remove tmp code and enable tests

    // function test_RevertIf_BaseAssetIsAttempted() public {
    //     _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

    //     address[] memory tokens = new address[](1);
    //     uint256[] memory amounts = new uint256[](1);
    //     address[] memory destinations = new address[](1);

    //     tokens[0] = address(vaultAsset);
    //     amounts[0] = 1e18;
    //     destinations[0] = address(this);

    //     vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowed.selector, address(vaultAsset)));
    //     vault.recover(tokens, amounts, destinations);
    // }

    // function test_RevertIf_DestinationVaultIsAttempted() public {
    //     _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

    //     address[] memory tokens = new address[](1);
    //     uint256[] memory amounts = new uint256[](1);
    //     address[] memory destinations = new address[](1);

    //     address dv = address(
    //         _setupDestinationVault(
    //             DVSetup({
    //                 lmpVault: vault,
    //                 dvSharesToLMP: 10e18,
    //                 valuePerShare: 1e18,
    //                 minDebtValue: 5e18,
    //                 maxDebtValue: 15e18,
    //                 lastDebtReportTimestamp: block.timestamp
    //             })
    //         )
    //     );

    //     tokens[0] = address(dv);
    //     amounts[0] = 1e18;
    //     destinations[0] = address(this);

    //     assertEq(vault.isDestinationRegistered(dv), true, "destinationRegistered");

    //     vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowed.selector, dv));
    //     vault.recover(tokens, amounts, destinations);
    // }
}

contract PeriodicFees is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();

        vault.useRealCollectFees();
    }

    function test_IsSetOnInitialization() public {
        assertGt(vault.getFeeSettings().lastPeriodicFeeTake, 0);
    }

    function test_CannotSetPeriodicFee_OverMax() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);
        vm.expectRevert(abi.encodeWithSignature("InvalidFee(uint256)", 1e18));

        vault.setPeriodicFeeBps(1e18);
    }

    function test_ProperlySetsFee_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);

        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeSet(500);

        vault.setPeriodicFeeBps(500);
    }

    function test_CollectsPeriodicFeeCorrectly() public {
        // Grant roles
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_PERIODIC_FEE_SETTER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, true);

        //
        // First fee take set up, execution, and checks.
        //

        // Local variables.
        uint256 warpAmount = block.timestamp + 1 days; // Calc fee for one day passing btwn debt reportings.
        uint256 depositAmount = 3e20;
        uint256 periodicFeeBps = 500; // 5%
        address feeSink = makeAddr("periodicFeeSink");
        uint256 expectedLastPeriodicFeeTake = warpAmount;

        // Mint, approve, deposit to give supply, record supply.
        vaultAsset.mint(address(this), type(uint256).max);
        vaultAsset.approve(address(vault), type(uint256).max);
        vault.deposit(depositAmount, address(this));
        uint256 vaultTotalSupplyFirstDeposit = vault.totalSupply();

        // Set fee and sink.
        vault.setPeriodicFeeBps(periodicFeeBps);
        vault.setPeriodicFeeSink(feeSink);

        // Warp block.timestamp to allow for fees to be taken.
        vm.warp(warpAmount);

        // Externally calculated fees in asset
        uint256 expectedFees = 41_097_000_000_000_000;

        // Externally calculated shares
        uint256 calculatedShares = 41_102_630_649_372_658;

        // Update debt, check events.
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(vault), feeSink, 0, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeCollected(expectedFees, feeSink, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit LastPeriodicFeeTakeSet(expectedLastPeriodicFeeTake);
        vault.updateDebtReporting(0);

        uint256 minted = vault.balanceOf(feeSink);

        // Check that correct numbers have been minted.
        assertEq(minted, calculatedShares, "shares");
        assertEq(vaultTotalSupplyFirstDeposit + minted, vault.totalSupply(), "totalSupply");
        assertEq(vault.getFeeSettings().lastPeriodicFeeTake, expectedLastPeriodicFeeTake, "lastFeeTakeTime");

        //
        // Second fee take.
        //

        // Increase deposits, longer time between fee takes.
        warpAmount = block.timestamp + 25 days;
        depositAmount = 1500e18;
        expectedLastPeriodicFeeTake = warpAmount;
        vault.deposit(depositAmount, address(this));

        // Snapshot vault supply after second deposit
        uint256 vaultSupplySecondDeposit = vault.totalSupply();

        vm.warp(warpAmount);

        // Externally calculated fees in asset
        expectedFees = 6_164_388_000_000_000_000;

        // Externally calculated shares
        calculatedShares = 6_186_418_956_754_918_383;

        // Update debt, check events.
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(vault), feeSink, 0, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeCollected(expectedFees, feeSink, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit LastPeriodicFeeTakeSet(expectedLastPeriodicFeeTake);
        vault.updateDebtReporting(0);

        // Fee sink balance minus balance from first mint.
        uint256 mintedSecondClaim = vault.balanceOf(feeSink) - minted;

        assertEq(mintedSecondClaim, calculatedShares, "shares");
        assertEq(vaultSupplySecondDeposit + mintedSecondClaim, vault.totalSupply(), "totalSupply");
        assertEq(vault.getFeeSettings().lastPeriodicFeeTake, expectedLastPeriodicFeeTake, "lastFeeTakeTime");

        //
        // Third fee take.
        //

        // No new deposit, change up fee, much longer time between fee takes.
        warpAmount = block.timestamp + 545 days;
        periodicFeeBps = 150; // 1.5%
        expectedLastPeriodicFeeTake = warpAmount;

        // Set new fee.
        vault.setPeriodicFeeBps(periodicFeeBps);

        // Vault supply pre third fee take, no update from deposit for this one.
        uint256 vaultSupplyThirdFeeTake = vault.totalSupply();

        vm.warp(warpAmount);

        // Externally calculated fees in asset
        expectedFees = 40_315_086_000_000_000_000;

        // Externally calculated shares
        calculatedShares = 41_386_104_165_242_811_750;

        // Update debt, check events.
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(vault), feeSink, 0, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit PeriodicFeeCollected(expectedFees, feeSink, calculatedShares);
        vm.expectEmit(false, false, false, true);
        emit LastPeriodicFeeTakeSet(expectedLastPeriodicFeeTake);
        vault.updateDebtReporting(0);

        // Third mint to fee sink address.
        uint256 mintedThirdClaim = vault.balanceOf(feeSink) - mintedSecondClaim - minted;

        // Check that correct numbers have been minted.
        assertEq(mintedThirdClaim, calculatedShares, "shares");
        assertEq(vaultSupplyThirdFeeTake + mintedThirdClaim, vault.totalSupply(), "totalSupply");
        assertEq(vault.getFeeSettings().lastPeriodicFeeTake, expectedLastPeriodicFeeTake, "lastFeeTakeTime");
    }

    function test_LastPeriodicFeeTake_StillUpdatedWhen_FeeNotTaken() public {
        // Grant roles
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, true);

        // Local vars.
        uint256 warpAmount = block.timestamp + 10 days;
        uint256 depositAmount = 1e18;
        uint256 expectedLastPeriodicFeeTake = warpAmount;

        // Mint, approve, deposit to give supply.
        vaultAsset.mint(address(this), depositAmount);
        vaultAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        assertEq(vault.getFeeSettings().periodicFeeSink, address(0));
        assertEq(vault.getFeeSettings().periodicFeeBps, 0);

        // Warp
        vm.warp(warpAmount);

        // Call updateDebtReporting to actually his _collectFees, check events emitted, etc.
        vm.expectEmit(false, false, false, true);
        emit LastPeriodicFeeTakeSet(expectedLastPeriodicFeeTake);
        vault.updateDebtReporting(0);

        // Post operation checks.
        assertEq(vault.getFeeSettings().lastPeriodicFeeTake, expectedLastPeriodicFeeTake);
    }
}

contract TransferTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_RevertIf_TransferPaused() public {
        address recipient = address(4);
        address user = address(5);

        vaultAsset.mint(address(this), 1000);
        vaultAsset.approve(address(vault), 1000);
        vault.mint(1000, address(this));

        vault.approve(user, 500);

        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        vault.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.transferFrom(address(this), recipient, 10);
        vm.stopPrank();
    }

    function test_RevertIf_TransferFromPaused() public {
        address recipient = address(4);
        address user = address(5);

        vaultAsset.mint(address(this), 1000);
        vaultAsset.approve(address(vault), 1000);

        vault.mint(1000, address(this));

        vault.approve(user, 500);

        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);
        vault.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.transferFrom(address(this), recipient, 10);
        vm.stopPrank();
    }
}

contract SetSymbolAndDescTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_EmitsEvent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        vm.expectEmit(true, true, true, true);
        emit SymbolAndDescSet("A", "B");
        vault.setSymbolAndDescAfterShutdown("A", "B");
    }

    function test_SetsNewSymbolAndName() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        string memory newSymbol = "A";
        string memory newName = "B";

        assertTrue(
            keccak256(abi.encodePacked(vault.symbol())) != keccak256(abi.encodePacked(newSymbol)), "symbolBefore"
        );
        assertTrue(keccak256(abi.encodePacked(vault.name())) != keccak256(abi.encodePacked(newName)), "nameBefore");

        vault.setSymbolAndDescAfterShutdown("A", "B");

        assertEq(vault.symbol(), newSymbol, "symbol");
        assertEq(vault.name(), newName, "name");
    }

    function test_RevertIf_NotCalledByAdmin() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setSymbolAndDescAfterShutdown("A", "B");

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
        vault.setSymbolAndDescAfterShutdown("A", "B");
    }

    function test_RevertIf_VaultIsNotShutdown() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

        vm.expectRevert(
            abi.encodeWithSelector(ILMPVault.InvalidShutdownStatus.selector, ILMPVault.VaultShutdownStatus.Active)
        );
        vault.setSymbolAndDescAfterShutdown("A", "B");

        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        vault.setSymbolAndDescAfterShutdown("A", "B");
    }

    function test_RevertIf_NewSymbolIsBlank() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "newSymbol"));
        vault.setSymbolAndDescAfterShutdown("", "B");
        vault.setSymbolAndDescAfterShutdown("A", "B");
    }

    function test_RevertIf_NewNameIsBlank() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "newName"));
        vault.setSymbolAndDescAfterShutdown("A", "");
        vault.setSymbolAndDescAfterShutdown("A", "B");
    }
}

contract RedeemTests is LMPVaultTests {
    using WithdrawalQueue for StructuredLinkedList.List;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_IdleAssetsUsedWhenAvailable() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 sharesReceived = _depositFor(user, depositAmount);

        assertEq(vault.getAssetBreakdown().totalIdle, depositAmount);
        assertEq(vault.getAssetBreakdown().totalDebt, 0);

        uint256 prevAssetBalance = vaultAsset.balanceOf(user);
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(sharesReceived, user, user);
        uint256 newAssetBalance = vaultAsset.balanceOf(user);

        assertEq(vault.totalIdle(), 0);
        assertEq(prevAssetBalance + assetsReceived, depositAmount);
        assertEq(newAssetBalance - assetsReceived, prevAssetBalance);
        assertEq(assetsReceived, depositAmount);
    }

    function test_IdleAssetsUsedWhenAvailablePartial() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 withdrawAmount = 5e18;
        _depositFor(user, depositAmount);

        assertEq(vault.totalIdle(), depositAmount);
        assertEq(vault.totalDebt(), 0);

        uint256 prevAssetBalance = vaultAsset.balanceOf(user);
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(withdrawAmount, user, user);
        uint256 newAssetBalance = vaultAsset.balanceOf(user);

        assertEq(vault.totalIdle(), depositAmount - withdrawAmount);
        assertEq(prevAssetBalance + assetsReceived, withdrawAmount);
        assertEq(newAssetBalance - assetsReceived, prevAssetBalance);
        assertEq(assetsReceived, withdrawAmount);
    }

    function test_PullsFromWithdrawalQueueSimpleOneToOne() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        uint256 userShares = _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(0.1e9);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);

        // They were worth 10 but we experienced .1 slippage
        assertEq(assetsReceived, 9.9e9, "assetsReceived");

        // We should have cleared everything since we burned all shares
        assertEq(vault.totalIdle(), 0, "totalIdle");
        assertEq(vault.totalDebt(), 0, "totalDebt");
        assertEq(vault.totalDebtMin(), 0, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 0, "totalDebtMax");
    }

    function test_PartiallyDecreasesDebtNumbers() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        uint256 userShares = _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(0.1e9);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares / 2, user, user);

        // They were worth 5, 10 total but we burned half shares, and we experienced .1 slippage
        assertEq(assetsReceived, 4.9e9, "assetsReceived");

        // We should have cleared everything since we burned all shares
        assertEq(vault.totalIdle(), 0, "totalIdle");

        assertEq(vault.totalDebt(), 5e9, "totalDebt");
        assertEq(vault.totalDebtMin(), 4.995e9, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 5.005e9, "totalDebtMax");
    }

    function test_PositiveSlippageDropsIntoIdle() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9.99e9,
                maxDebtValue: 10.01e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        uint256 userShares = _depositFor(user, 10e9);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        dv1.setWithdrawBaseAssetSlippage(-1e9);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares / 2, user, user);

        // They were worth 4.995, 9.99 (minDebt) total but we burned half shares
        assertEq(assetsReceived, 4.995e9, "assetsReceived");

        // We received positive slippage, so into idle it goes
        // And minor difference in minDebt and actual .005 goes into idle as well
        assertEq(vault.totalIdle(), 1.005e9, "totalIdle");

        assertEq(vault.totalDebt(), 5e9, "totalDebt");
        assertEq(vault.totalDebtMin(), 4.995e9, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 5.005e9, "totalDebtMax");
    }

    function test_AssetsGoToReceiver() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 amount = 9e18;
        uint256 prevBalance = vaultAsset.balanceOf(user2);
        uint256 shares = _depositFor(user1, amount);

        vm.prank(user1);
        vault.redeem(shares, user2, user1);

        uint256 newBalance = vaultAsset.balanceOf(user2);

        assertEq(amount, newBalance - prevBalance, "newBalance");
    }

    function test_EmitsWithdrawEvent() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        _depositFor(user1, 5e9);

        vault.setTotalIdle(4e9);

        // 2.4 assets = 3 (assets) * 4 (totalAssets) /  5 (totalSupply)
        uint256 assets = vault.convertToAssets(3e9);

        vm.expectEmit(true, true, true, true);

        emit Withdraw(user1, user2, user1, 2.4e9, 3e9);
        vm.prank(user1);
        vault.redeem(3e9, user2, user1);

        assertEq(assets, 2.4e9, "assets");
    }

    function test_EmitsNavEvent() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 sharesReceived = _depositFor(user1, 5e9);

        vault.setTotalIdle(4e9);

        // 2.4 assets = 3 (assets) * 4 (totalAssets) /  5 (totalSupply)
        uint256 assets = vault.convertToAssets(3e9);

        vm.expectEmit(true, true, true, true);

        emit Nav(4e9 - 2.4e9, 0, sharesReceived - 3e9);
        vm.prank(user1);
        vault.redeem(3e9, user2, user1);

        assertEq(assets, 2.4e9, "assets");
    }

    function test_AssetsReturnedBasedOnMinTotalAssets() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        _depositFor(user1, 10e9);

        // Mimic a deployment
        _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 5e9,
                maxDebtValue: 15e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        vault.setTotalIdle(0);

        uint256 snapshotId = vm.snapshot();

        // We try to request more than we have overall, which is the min debt value of dv1, 5e18
        vm.prank(user1);
        uint256 assetsRetrievedS1 = vault.redeem(5e9, user2, user1);
        assertEq(assetsRetrievedS1, 2.5e9, "scenario2.assetsRetrievedS1");
        vm.revertTo(snapshotId);

        // Pulling the full amount of debt, so all shares burned
        vm.prank(user1);
        uint256 assetsRetrievedS2 = vault.redeem(10e9, user2, user1);
        assertEq(assetsRetrievedS2, 5e9, "scenario2.assetsRetrieved");
        vm.revertTo(snapshotId);
    }

    function test_AssetsComeFromIdleOneToOneInitially() public {
        uint256 amount = 100_000;
        address user = makeAddr("user");
        uint256 sharesReceived = _depositFor(user, amount);

        assertEq(vault.getAssetBreakdown().totalIdle, amount, "beginIdle");

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(sharesReceived, user, user);

        assertEq(amount, sharesReceived, "sharesReceived");
        assertEq(amount, assetsReceived, "assetsReceived");
        assertEq(vault.getAssetBreakdown().totalIdle, 0, "newIdle");
    }

    function test_ExhaustedDestinationsAreRemovedFromWithdrawalQueue() public {
        address user = makeAddr("user1");
        DestinationVaultFake dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 9.99e18,
                maxDebtValue: 10.01e18,
                lastDebtReportTimestamp: block.timestamp
            })
        );
        uint256 userShares = _depositFor(user, 10e18);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        assertEq(vault.isInWithdrawalQueue(address(dv1)), true);

        vm.prank(user);
        vault.redeem(userShares, user, user);

        assertEq(vault.isInWithdrawalQueue(address(dv1)), false);
    }

    function test_UserReceivesNoMoreThanCachedValueIfValueIncreases() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        // Deployed 200 assets to DV1
        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 100e9,
                valuePerShare: 2e9,
                minDebtValue: 1.95e9 * 100,
                maxDebtValue: 2.05e9 * 100,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Deployed 800 assets to DV1
        DestinationVaultFake destVault2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        vault.setTotalIdle(0);

        // We want to mimic double the value of DV1 so we'll set
        // some positive slippage on the withdrawBaseAsset so we get back more than we'd expect
        destVault1.setWithdrawBaseAssetSlippage(-50e9);

        destVault2.setWithdrawBaseAssetSlippage(-100e9);

        // Cashing in 900 shares means we're entitled to at most
        // 900 (shares) * 955 (minTotalAssets) / 1000 (totalSupply) = 859.5 assets

        // We can get 250 (200 value and 50 positive slippage) from DV1 which means we have to get the remaining 609.5
        // from DV2. The amount we are trying to pull is more than DV1 is worth so we'll exhaust the whole thing.
        // So again, the 250 we get from there. For DV2, we only need to use a
        // portion so we calculate how many shares we should burn based on the min value.
        // Thats a total of 760e18 value over 800 shares so roughly ~641.578 shares
        // Those shares are worth 1:1 plus the 100 positive slippage we get will get ~741.578 ETH.
        // That covers the 609.5 we're trying to get and the difference of ~132 drops into idle

        uint256 idleBefore = vault.totalIdle();
        uint256 assetBalBefore = vaultAsset.balanceOf(user);
        uint256 dv1ShareBalBefore = destVault1.balanceOf(address(vault));
        uint256 dv2ShareBalBefore = destVault2.balanceOf(address(vault));

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(900e9, user, user);
        uint256 assetBalAfter = vaultAsset.balanceOf(user);
        uint256 idleAfter = vault.totalIdle();

        assertEq(idleBefore, 0, "idleBefore");

        // Extra assets from dv2 drop into idle
        assertEq(idleAfter, 132.078947368e9, "idleAfter");
        assertEq(assetsReceived, 859.5e9, "returned");
        assertEq(assetBalAfter - assetBalBefore, 859.5e9, "actual");
        assertEq(dv1ShareBalBefore, 100e9, "dv1ShareBalBefore");
        assertEq(destVault1.balanceOf(address(vault)), 0, "dv1ShareBalAfter");
        assertEq(dv2ShareBalBefore, 800e9, "dv2ShareBalBefore");

        // 800 - ~641.578 shares we burned
        assertEq(destVault2.balanceOf(address(vault)), 158.421052632e9, "dv2ShareBalAfter");
    }

    function test_UserReceivesLessAssetsIfPricesDrops() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        // Deployed 200 assets to DV1
        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 100e9,
                valuePerShare: 2e9,
                minDebtValue: 1.95e9 * 100,
                maxDebtValue: 2.05e9 * 100,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Deployed 800 assets to DV1
        DestinationVaultFake destVault2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        // Mimicking a price drop through our slippage params
        destVault1.setWithdrawBaseAssetSlippage(50e9);
        destVault2.setWithdrawBaseAssetSlippage(100e9);

        // Cashing in 500 shares means we're entitled to at most
        // 500 (shares) * 955 (minTotalAssets) / 1000 (totalSupply) = 477.5 assets

        // We think we can get 195 from DV1 but with our 50 of slippage we have set
        // we'll only get 150 back. We charge for the 195 though so that means we will try to get
        // 282.5 from DV2. We have a total of 760e18 value over 800 shares so for that amount its
        // ~297.37 shares. They're priced 1:1 atm but with our 100 slippage we only get 197.37 back
        // This leaves us with 150 + 197.37 or 347.4 of actual assets coming back

        vault.setTotalIdle(0);

        uint256 idleBefore = vault.totalIdle();
        uint256 assetBalBefore = vaultAsset.balanceOf(user);
        uint256 dv1ShareBalBefore = destVault1.balanceOf(address(vault));
        uint256 dv2ShareBalBefore = destVault2.balanceOf(address(vault));

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(500e9, user, user);
        uint256 assetBalAfter = vaultAsset.balanceOf(user);
        uint256 idleAfter = vault.totalIdle();

        // No extra so no idle increase
        assertEq(idleBefore, 0, "idleBefore");
        assertEq(idleAfter, 0, "idleAfter");

        assertEq(assetsReceived, 347.368421052e9, "returned");
        assertEq(assetBalAfter - assetBalBefore, 347.368421052e9, "actual");
        assertEq(dv1ShareBalBefore, 100e9, "dv1ShareBalBefore");
        assertEq(destVault1.balanceOf(address(vault)), 0, "dv1ShareBalAfter");
        assertEq(dv2ShareBalBefore, 800e9, "dv2ShareBalBefore");

        // 800 - ~297.37 shares we burned
        assertEq(destVault2.balanceOf(address(vault)), 502.631578948e9, "dv2ShareBalAfter");
    }

    function test_StaleDestinationIsRepriced() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        address user = makeAddr("user");
        uint256 amount = 1000e9;
        _depositFor(user, amount);

        DestinationVaultFake destVault1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 800e9,
                valuePerShare: 1e9,
                minDebtValue: 0.95e9 * 800,
                maxDebtValue: 1.05e9 * 800,
                lastDebtReportTimestamp: block.timestamp - 2 days // Make the data stale
             })
        );

        vault.setTotalIdle(0);

        // Get how many shares we'd expect this to take
        // 1 * 760 / 1000 = .76
        uint256 calculatedAssets = vault.convertToAssets(1e9, ILMPVault.TotalAssetPurpose.Withdraw);

        // We knock the price of our assets nearly in half though
        // 1 * 400 / 100 = .4
        _mockDestVaultFloorPrice(address(destVault1), 0.5e9);

        vm.prank(user);
        uint256 actualAssets = vault.redeem(1e9, user, user);

        assertEq(calculatedAssets, 0.76e9, "calc");
        assertEq(actualAssets, 0.4e9, "actual");
        assertTrue(actualAssets < calculatedAssets, "shares");
    }

    function test_RedeemPossibleIfVaultIsShutdown() public {
        address user = makeAddr("user");
        _depositFor(user, 2e9);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(vaultAsset.balanceOf(user), 0, "prevBal");

        vm.prank(user);
        vault.redeem(1e9, user, user);

        assertEq(vaultAsset.balanceOf(user), 1e9, "newBal");
    }

    function test_RevertIf_NavDecreases() public {
        address user = makeAddr("user");
        _depositFor(user, 2e18);

        // vaultAsset.mint(address(this), 1e18);
        // vaultAsset.approve(address(vault), 1e18);

        vault.setNextWithdrawHalvesIdle();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavDecreased.selector, 10_000, 5000));
        vault.redeem(1e18, user, user);
        vm.stopPrank();
    }

    function test_RevertIf_SystemIsMidNavChange() public {
        address user = makeAddr("user");
        _depositFor(user, 2e9);

        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        vault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

        assertEq(vaultAsset.balanceOf(user), 0, "prevBal");

        _mockSysSecurityNavOpsInProgress(systemSecurity, 1);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(LMPVault.NavOpsInProgress.selector));
        vault.redeem(1e9, user, user);
        vm.stopPrank();

        assertEq(vaultAsset.balanceOf(user), 0, "interimBal");

        _mockSysSecurityNavOpsInProgress(systemSecurity, 0);

        vm.startPrank(user);
        vault.redeem(1e9, user, user);
        vm.stopPrank();
        assertEq(vaultAsset.balanceOf(user), 1e9, "newBal");
    }

    function test_RevertIf_PausedLocally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        address user = makeAddr("user");
        uint256 shares = _depositFor(user, 2e18);

        vault.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.redeem(1e18, user, user);
        vm.stopPrank();

        vault.unpause();

        assertEq(vault.balanceOf(user), shares, "shares");
    }

    function test_RevertIf_PausedGlobally() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);

        address user = makeAddr("user");
        uint256 shares = _depositFor(user, 2e18);

        _mockSysSecurityIsSystemPaused(systemSecurity, true);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.IsPaused.selector));
        vault.redeem(1e18, user, user);
        vm.stopPrank();

        _mockSysSecurityIsSystemPaused(systemSecurity, false);

        assertEq(vault.balanceOf(user), shares, "shares");
    }

    function test_RevertIf_AssetsReceivedWouldBeZero() public {
        address user = makeAddr("user");
        _depositFor(user, 2e9);

        vault.setTotalIdle(1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "possibleAssets"));
        vm.prank(user);
        vault.redeem(1e9, user, user);

        vault.setTotalIdle(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "possibleAssets"));
        vm.prank(user);
        vault.redeem(1e9, user, user);

        vault.setTotalIdle(2e9);
        vm.prank(user);
        vault.redeem(1e9, user, user);

        assertEq(vaultAsset.balanceOf(user), 1e9, "newBal");
    }
}

contract FeeAndProfitTests is LMPVaultTests {
    using Math for uint256;

    struct ProfitSetupState {
        uint256 lastUnlockTime;
        uint48 unlockPeriodInSeconds;
        uint256 currentShares;
        uint256 currentProfitUnlockRate;
        uint256 fullProfitUnlockTime;
    }

    function setUp() public virtual override {
        super.setUp();
    }

    function test_NoPreviousStateNoActionsPerformed() public {
        vault.feesAndProfitHandling(0, 0, 0);
    }

    function test_ProfitIsDistributedImmediately() public {
        // Profit is distributed immediately when there are no locking
        // settings configured
        uint256 existingTotalDebt = 10e18;
        uint256 newTotalDebt = 20e18;
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: 0,
                unlockPeriodInSeconds: 0, // The important one here
                currentShares: 0,
                currentProfitUnlockRate: 0,
                fullProfitUnlockTime: 0
            })
        );

        vault.setTotalDebt(newTotalDebt);

        // Not collecting any fees so we won't lower our profit shares minted
        vault.setFeeSharesToBeCollected(0);

        // Total supply is currently zero so calculated profit shares
        // Should equal the gain 1:1
        // Params here represent a gain of 10e18
        vault.feesAndProfitHandling(0, newTotalDebt, existingTotalDebt);

        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 0e18, "mintedShares");
    }

    function test_ProfitIsMintedAsSharesToVault() public {
        vault.mint(address(1), 90e18);

        // Not collecting any fees so we won't lower our profit shares minted
        vault.setFeeSharesToBeCollected(0);

        uint256 startingTotalDebt = 90e18;
        uint256 newTotalDebt = 100e18;
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: 0,
                unlockPeriodInSeconds: 1 days,
                currentShares: 0,
                currentProfitUnlockRate: 0,
                fullProfitUnlockTime: 0
            })
        );

        vault.setTotalDebt(newTotalDebt);

        // Params here represent a gain of 10e18
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Minted actual balance
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 10e18, "mintedShares");

        // Balance accounting for unlock period
        // At time 0, so none should be unlocked
        uint256 balT0 = vault.balanceOf(address(vault));
        assertEq(balT0, 10e18, "balT0");

        // Jump ahead half of the unlock period
        vm.warp(block.timestamp + (1 days / 2));

        // Nothing else has happened so the shares are still minted to the vault
        uint256 actualMid = vault.balanceOfActual(address(vault));
        assertEq(actualMid, 10e18, "actualMid");

        // But the time has passed so are reported balance is only half
        uint256 balHalfTime = vault.balanceOf(address(vault));
        assertEq(balHalfTime - 1 wei, /* unlocks rounded down */ 5e18, "balHalfTime");

        // Jump to the end of the unlock period
        vm.warp(block.timestamp + (1 days / 2));

        // Still nothing happened in the vault
        uint256 actualEnd = vault.balanceOfActual(address(vault));
        assertEq(actualEnd, 10e18, "actualEnd");

        // Should be fully unlocked, so the vault is credited with 0
        uint256 balEnd = vault.balanceOf(address(vault));
        assertEq(balEnd, 0, "balEnd");
    }

    function test_ProfitWontIncreaseNavPerShare() public {
        vault.mint(address(1), 80e18);
        vault.setTotalDebt(90e18);

        uint256 navPerShareStart = vault.convertToAssets(1e18);

        // Vault starts with 90 total assets
        assertEq(vault.totalAssets(), 90e18);

        // No Existing Profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: 0,
                unlockPeriodInSeconds: 1 days,
                currentShares: 0,
                currentProfitUnlockRate: 0,
                fullProfitUnlockTime: 0
            })
        );

        vault.setTotalDebt(100e18);

        // Vault started with 0 shares
        assertEq(vault.balanceOf(address(vault)), 0);

        // 10e18 Profit
        vault.feesAndProfitHandling(0, 100e18, 90e18);

        // Nav/share stayed the same
        assertEq(navPerShareStart, vault.convertToAssets(1e18), "navPerShareEnd");

        // While more shares were minted and total assets went up
        assertEq(vault.balanceOf(address(vault)), 8_888_888_888_888_888_888);
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_FeeSharesAreCoveredFullyByNewProfit() public {
        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 80e18);

        // 5 shares will be minted as fees
        vault.setFeeSharesToBeCollected(5e18);

        // Starting this process with 90e18 totalDebt
        uint256 startingDebt = 90e18;
        vault.setTotalDebt(startingDebt);

        uint256 navPerShareStart = vault.convertToAssets(1e18);

        uint256 newTotalDebt = 100e18;
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: 0,
                unlockPeriodInSeconds: 1 days,
                currentShares: 0,
                currentProfitUnlockRate: 0,
                fullProfitUnlockTime: 0
            })
        );

        vault.setTotalDebt(newTotalDebt);

        // Params here represent a gain of 10e18
        vault.feesAndProfitHandling(0, newTotalDebt, startingDebt);

        // Nav/share stayed the same
        assertEq(navPerShareStart, vault.convertToAssets(1e18), "navPerShareEnd");

        assertEq(vault.balanceOf(address(vault)), 3_888_888_888_888_888_888);
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_FeeSharesAreCoveredPartiallyByNewProfit() public {
        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 15 shares will be minted as fees
        vault.setFeeSharesToBeCollected(15e18);

        uint256 startingDebt = 90e18;
        vault.setTotalDebt(startingDebt);

        // 90 shares, 90 debt, 1:1, 1e18 nav/share
        uint256 navPerShareStart = vault.convertToAssets(1e18);
        assertEq(navPerShareStart, 1e18);

        uint256 newTotalDebt = 100e18;
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: 0,
                unlockPeriodInSeconds: 1 days,
                currentShares: 0,
                currentProfitUnlockRate: 0,
                fullProfitUnlockTime: 0
            })
        );

        vault.setTotalDebt(newTotalDebt);

        // Params here represent a gain of 10e18
        vault.feesAndProfitHandling(0, newTotalDebt, startingDebt);

        // Minted actual balance, 0, since fees ate everything
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 0, "mintedShares");

        // 90 original shares + 15 fee, 105 total with 100 assets
        uint256 navPerShareEnd = vault.convertToAssets(1e18);
        assertEq(uint256(100e18) * 1e18 / uint256(105e18), navPerShareEnd);
        assertTrue(navPerShareStart > navPerShareEnd, "navDecreased");
    }

    function test_FeeSharesAreCoveredFullyByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 2 shares will be minted as fees
        vault.setFeeSharesToBeCollected(2e18);

        uint256 startingTotalDebt = 100e18;
        uint256 newTotalDebt = 100e18;
        vault.setTotalDebt(startingTotalDebt);

        // We will also setup 10e18 shares currently unlock as profit
        // We are half way through the unlock period which means we should have
        // ~5 available from existing profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - 1 days / 2,
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + 1 days / 2
            })
        );

        uint256 startingNav = vault.convertToAssets(1e18);

        // 100e18 assets with the original 90 mint + the ~5 that are unlocked
        assertEq(startingNav, startingTotalDebt * 1e18 / (90e18 + 5e18 + 1), "startNavShare");

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 5e18 + 1, "remainingProfitBal");

        vault.setTotalDebt(newTotalDebt);

        uint256 previousUnlockTime = vault.getProfitUnlockSettings().fullProfitUnlockTime;

        // No new profit
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Ensure no change
        assertEq(vault.totalAssets(), 100e18, "totalAssetsResult");

        // Ensure nav didn't change since fee shares fully covered
        assertEq(startingNav, vault.convertToAssets(1e18), "newNavShare");

        // Minted actual balance
        // We had 5 shares before but used 2 of them to cover the fee
        // shares so we have 3 left
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 3e18 + 1, "mintedShares");

        // No new profit shares were minted either so the unlock
        // period should stay the same as it was
        assertEq(vault.getProfitUnlockSettings().fullProfitUnlockTime, previousUnlockTime, "unlockTime");

        // Jump ahead to the unlock time so we can ensure our total
        // amount is unlock
        vm.warp(previousUnlockTime);

        // The vault still technically has the remaining 3
        profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 3e18 + 1, "profitShareConfirmAfter");

        // But we're at the unlock so we're reporting none
        remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 0, "remainingProfitBalAfter");
    }

    function test_FeeSharesAreCoveredPartiallyByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 2 shares will be minted as fees
        vault.setFeeSharesToBeCollected(2e18);

        // We are 98% through the unlock which means we'll still have
        // .2 shares left to burn.
        uint256 startingTotalDebt = 100e18;
        vault.setTotalDebt(startingTotalDebt);

        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - (1 days * 98 / 100),
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + (1 days * 2 / 100)
            })
        );

        // 100 assets with 90 shares + that ~.2 that are still locked, (+1 for rounding)
        uint256 startingNavShare = vault.convertToAssets(1e18);
        assertEq(startingNavShare, startingTotalDebt * 1e18 / (90e18 + (10e18 * 2 / 100) + 1), "startNavShare");

        uint256 newTotalDebt = 100e18;
        vault.setTotalDebt(newTotalDebt);

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 0.2e18 + 1, "remainingProfitBal");

        // No new profit
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // We couldn't cover all the fees so we still see a decrease in nav/share
        uint256 endingNavShare = vault.convertToAssets(1e18);
        assertTrue(endingNavShare < startingNavShare, "endNavShareDecrease");
        // Still 100e18 assets, 90 original shares and the 2 fee shares, the .2 profit was burned
        assertEq(endingNavShare, startingTotalDebt * 1e18 / (90e18 + 2e18), "endNavShare");

        // Minted actual balance
        // We had 10 shares total with 98% of them available and burned above
        // That left .2 which were additionally burned to cover fees
        // So now we should have no shares
        profitShareConfirm = vault.balanceOfActual(address(vault));
        remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(profitShareConfirm, 0, "profitShareConfirmAfter");
        assertEq(remainingProfitBal, 0, "remainingProfitBalAfter");
    }

    function test_FeeSharesAreCoveredFullyByExistingAndNewProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 2 shares will be minted as fees
        vault.setFeeSharesToBeCollected(2e18);

        uint256 startTotalDebt = 90e18;
        vault.setTotalDebt(startTotalDebt);

        // We are 90% through the unlock which means we'll still have
        // ~1 shares left to burn.
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - (1 days * 90 / 100),
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + (1 days * 10 / 100)
            })
        );

        uint256 startingNavShare = vault.convertToAssets(1e18);
        // 90 assets / 90 original mint + ~1 still unlocking
        assertEq(startingNavShare, startTotalDebt * 1e18 / (90e18 + 1e18 + 1), "startingNavShare");

        uint256 newTotalDebt = 100e18;
        vault.setTotalDebt(newTotalDebt);

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");
        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 1e18 + 1, "remainingProfitBal");

        // 10e18 profit
        vault.feesAndProfitHandling(0, newTotalDebt, startTotalDebt);

        // There were ~91 shares and 90 assets going in. This meant a
        // nav/share of 90/91 = ~.989. With a new total assets of 100
        // that gives us a target total supply (so we see no nav/share change)
        // of 100 * ~91 / 90 = 101.111 (100/101.111 == ~.989).
        // We have a total supply of 90 + 2 (fees) + ~1 (remaining profit)
        // So we need to mint 101.111 - 93 or 8.111 shares giving us a total
        // of 9.111..2 locked shares

        profitShareConfirm = vault.balanceOfActual(address(vault));
        uint256 unlockedProfit = vault.balanceOf(address(vault));
        uint256 newLockShares = 9_111_111_111_111_111_112;
        assertEq(profitShareConfirm, newLockShares, "profitShareConfirmAfter");
        assertEq(unlockedProfit, newLockShares, "unlockedProfit");

        // We had 1.00..1 previous shares with (1 days * 10 / 100) time remaining
        // to unlock and 8.111 shares that would have the full unlock time of 1 day
        // Weighted avg to find the total unlock time of the set
        // ((1.00..1 * 8640) + (8.111 * 86400)) / 9.111..2 = ~77865
        assertEq(vault.getProfitUnlockSettings().fullProfitUnlockTime, block.timestamp + 77_865, "newUnlockTime");

        // Rate is the shares over the time period
        assertEq(
            vault.getProfitUnlockSettings().profitUnlockRate,
            newLockShares * AutoPoolFees.MAX_BPS_PROFIT / 77_865,
            "newUnlockRate"
        );

        // No change in nav/share
        assertEq(startingNavShare, vault.convertToAssets(1e18), "endNavShare");
    }

    function test_FeeSharesAreCoveredPartiallyByExistingAndNewProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 20 shares will be minted as fees
        vault.setFeeSharesToBeCollected(20e18);

        // We are 90% through the unlock which means we'll still have
        // ~1 shares left to burn.
        uint256 startingTotalDebt = 90e18;
        vault.setTotalDebt(startingTotalDebt);
        uint256 startNavShare = vault.convertToAssets(1e18);

        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - (1 days * 90 / 100),
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + (1 days * 10 / 100)
            })
        );

        uint256 newTotalDebt = 100e18;
        vault.setTotalDebt(newTotalDebt);

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");
        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 1e18 + 1, "remainingProfitBal");

        // 10e18 profit
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Even with 10e18 profit and 1 remaining share we couldn't cover
        // The new fees so existing profit share was burnt and new profit
        // didn't result in a new mint
        profitShareConfirm = vault.balanceOfActual(address(vault));
        uint256 unlockedProfit = vault.balanceOf(address(vault));
        assertEq(profitShareConfirm, 0, "profitShareConfirmAfter");
        assertEq(unlockedProfit, 0, "unlockedProfit");

        // No profit shares so no unlock rate
        assertEq(vault.getProfitUnlockSettings().profitUnlockRate, 0, "profitUnlockRate");

        // We weren't able to cover the new fees so nav/share took a hit
        // 100e18 assets across 110 shares
        // 110 = 90 original, 20 new fees, and we burned the ~1 existing profit
        uint256 newNavShare = vault.convertToAssets(1e18);
        assertEq(newNavShare, 909_090_909_090_909_090);

        // However the new nav/share is better than if we hadn't used
        // our existing profit to try and cover
        assertTrue(newNavShare > (100e18 / uint256(90e18 + 20e18 + 1e18 + 1)), "potentialNavShare");

        // But ultimately we saw a drop
        assertTrue(startNavShare > newNavShare, "navShareDropped");
    }

    function test_LossesAreCoveredFullyByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // No fees
        vault.setFeeSharesToBeCollected(0e18);

        uint256 startingTotalDebt = 100e18;
        uint256 newTotalDebt = 98e18;
        vault.setTotalDebt(startingTotalDebt);

        // We will also setup 10e18 shares currently unlock as profit
        // We are half way through the unlock period which means we should have
        // ~5 available from existing profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - 1 days / 2,
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + 1 days / 2
            })
        );

        uint256 startingNav = vault.convertToAssets(1e18);

        // 100e18 assets with the original 90 mint + the ~5 that are unlocked
        assertEq(startingNav, startingTotalDebt * 1e18 / (90e18 + 5e18 + 1), "startNavShare");

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 5e18 + 1, "remainingProfitBal");

        vault.setTotalDebt(newTotalDebt);

        uint256 previousUnlockTime = vault.getProfitUnlockSettings().fullProfitUnlockTime;

        // 2e18 loss
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Ensure total assets are what we think
        assertEq(vault.totalAssets(), 98e18, "totalAssetsResult");

        // Ensure nav didn't change since the loss should be covered by
        // unlocking more profit shares
        assertEq(startingNav, vault.convertToAssets(1e18), "newNavShare");

        // We had ~95 share and 100 assets going into this. Nav/share 1.05
        // To keep it there with 98 assets we'd need total supply to be
        // at ~93.1 so burned ~1.9 of our profit shares.
        // ~5 - ~1.9 = 3.1

        // Minted actual balance
        // We had ~5 shares before but used 2 of them to cover the fee
        // shares so we have 3 left
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 3.1e18, "mintedShares");

        // No new profit shares were minted either so the unlock
        // period should stay the same as it was
        assertEq(vault.getProfitUnlockSettings().fullProfitUnlockTime, previousUnlockTime, "unlockTime");

        // Jump ahead to the unlock time so we can ensure our total
        // amount is unlock
        vm.warp(previousUnlockTime);

        // The vault still technically has the remaining 3
        profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 3.1e18, "profitShareConfirmAfter");

        // But we're at the unlock so we're reporting none
        remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 0, "remainingProfitBalAfter");
    }

    function test_LossesAreCoveredPartiallyByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // No fees
        vault.setFeeSharesToBeCollected(0e18);

        uint256 startingTotalDebt = 100e18;
        uint256 newTotalDebt = 90e18;
        vault.setTotalDebt(startingTotalDebt);

        // We will also setup 10e18 shares currently unlock as profit
        // We are half way through the unlock period which means we should have
        // ~5 available from existing profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - 1 days / 2,
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + 1 days / 2
            })
        );

        uint256 startingNav = vault.convertToAssets(1e18);

        // 100e18 assets with the original 90 mint + the ~5 that are unlocked
        assertEq(startingNav, startingTotalDebt * 1e18 / (90e18 + 5e18 + 1), "startNavShare");

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 5e18 + 1, "remainingProfitBal");

        vault.setTotalDebt(newTotalDebt);

        // 10e18 loss
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Ensure total assets are what we think
        assertEq(vault.totalAssets(), 90e18, "totalAssetsResult");

        // We expect nav/share to decrease since our profit unlock
        // won't cover everything
        uint256 endNavShare = vault.convertToAssets(1e18);
        assertTrue(startingNav > endNavShare, "newNavLower");

        // We had ~95 share and 100 assets going into this. Nav/share 1.05
        // To keep it there with 90 assets we'd need total supply to be
        // at ~85.5. We only had 5 left in profit so we burn them all
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 0e18, "mintedShares");

        // No profit shares so rate goes to 0
        assertEq(vault.getProfitUnlockSettings().profitUnlockRate, 0, "profitUnlockRate");

        // And just confirm that the only shares that exist are the original 90
        assertEq(vault.totalSupply(), 90e18, "finalShares");
    }

    function test_LossesAndFeesAreCoveredFullByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 2e18 fees
        vault.setFeeSharesToBeCollected(2e18);

        uint256 startingTotalDebt = 100e18;
        uint256 newTotalDebt = 98e18;
        vault.setTotalDebt(startingTotalDebt);

        // We will also setup 10e18 shares currently unlock as profit
        // We are half way through the unlock period which means we should have
        // ~5 available from existing profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - 1 days / 2,
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + 1 days / 2
            })
        );

        uint256 startingNav = vault.convertToAssets(1e18);

        // 100e18 assets with the original 90 mint + the ~5 that are unlocked
        assertEq(startingNav, startingTotalDebt * 1e18 / (90e18 + 5e18 + 1), "startNavShare");

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 5e18 + 1, "remainingProfitBal");

        vault.setTotalDebt(newTotalDebt);

        uint256 previousUnlockTime = vault.getProfitUnlockSettings().fullProfitUnlockTime;

        // 2e18 loss
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Ensure total assets are what we think
        assertEq(vault.totalAssets(), 98e18, "totalAssetsResult");

        // Ensure nav didn't change since the loss should be covered by
        // unlocking more profit shares
        assertEq(startingNav, vault.convertToAssets(1e18), "newNavShare");

        // We had ~95 share and 100 assets going into this. Nav/share 1.05
        // To keep it there with 98 assets we'd need total supply to be
        // at ~93.1. We minted 2 shares for fees so that puts us at 97
        // and so we need to burn 3.9 of are remaining 5 profit shares

        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 1.1e18, "mintedShares");

        // No new profit shares were minted either so the unlock
        // period should stay the same as it was
        assertEq(vault.getProfitUnlockSettings().fullProfitUnlockTime, previousUnlockTime, "unlockTime");

        // Jump ahead to the unlock time so we can ensure our total
        // amount is unlock
        vm.warp(previousUnlockTime);

        // The vault still technically has the remaining 3
        profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 1.1e18, "profitShareConfirmAfter");

        // But we're at the unlock so we're reporting none
        remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 0, "remainingProfitBalAfter");
    }

    function test_LossesAndFeesAreCoveredPartiallyByExistingProfit() public {
        vm.warp(1000 days);

        // Vault has a total supply of 90 shares going into
        // the fee and profit stage
        vault.mint(address(1), 90e18);

        // 2e18 fees
        vault.setFeeSharesToBeCollected(2e18);

        uint256 startingTotalDebt = 100e18;
        uint256 newTotalDebt = 90e18;
        vault.setTotalDebt(startingTotalDebt);

        // We will also setup 10e18 shares currently unlock as profit
        // We are half way through the unlock period which means we should have
        // ~5 available from existing profit
        _setupProfitState(
            ProfitSetupState({
                lastUnlockTime: block.timestamp - 1 days / 2,
                unlockPeriodInSeconds: 1 days,
                currentShares: 10e18,
                currentProfitUnlockRate: 10e18 * AutoPoolFees.MAX_BPS_PROFIT / 1 days,
                fullProfitUnlockTime: block.timestamp + 1 days / 2
            })
        );

        uint256 startingNav = vault.convertToAssets(1e18);

        // 100e18 assets with the original 90 mint + the ~5 that are unlocked
        assertEq(startingNav, startingTotalDebt * 1e18 / (90e18 + 5e18 + 1), "startNavShare");

        // Confirm our profit shares going into the fee handling
        uint256 profitShareConfirm = vault.balanceOfActual(address(vault));
        assertEq(profitShareConfirm, 10e18, "profitShareConfirm");

        uint256 remainingProfitBal = vault.balanceOf(address(vault));
        assertEq(remainingProfitBal, 5e18 + 1, "remainingProfitBal");

        vault.setTotalDebt(newTotalDebt);

        // 10e18 loss
        vault.feesAndProfitHandling(0, newTotalDebt, startingTotalDebt);

        // Ensure total assets are what we think
        assertEq(vault.totalAssets(), 90e18, "totalAssetsResult");

        // We expect nav/share to decrease since our profit unlock
        // won't cover everything
        uint256 endNavShare = vault.convertToAssets(1e18);
        assertTrue(startingNav > endNavShare, "newNavLower");

        // We had ~95 share and 100 assets going into this. Nav/share 1.05
        // To keep it there with 90 assets we'd need total supply to be
        // at ~85.5. We only had 5 left in profit so we burn them all
        uint256 mintedShares = vault.balanceOfActual(address(vault));
        assertEq(mintedShares, 0e18, "mintedShares");

        // No profit shares so rate goes to 0
        assertEq(vault.getProfitUnlockSettings().profitUnlockRate, 0, "profitUnlockRate");

        // And just confirm that the only shares that exist are the original 90 = 2 fees
        assertEq(vault.totalSupply(), 92e18, "finalShares");
    }

    function _setupProfitState(ProfitSetupState memory state) internal {
        vault.setLastProfitUnlockTime(state.lastUnlockTime);
        vault.setUnlockPeriodInSeconds(state.unlockPeriodInSeconds);
        if (state.currentShares > 0) {
            vault.mint(address(vault), state.currentShares);
        }
        vault.setProfitUnlockRate(state.currentProfitUnlockRate);
        vault.setFullProfitUnlockTime(state.fullProfitUnlockTime);
    }
}

contract FlashRebalanceTests is LMPVaultTests {
    DestinationVaultFake internal dv1;
    DestinationVaultFake internal dv2;
    TokenReturnSolver internal solver;

    function setUp() public virtual override {
        super.setUp();

        dv1 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 0e9,
                valuePerShare: 1e9,
                minDebtValue: 0e9,
                maxDebtValue: 0e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        dv2 = _setupDestinationVault(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 0e9,
                valuePerShare: 1e9,
                minDebtValue: 0e9,
                maxDebtValue: 0e9,
                lastDebtReportTimestamp: block.timestamp
            })
        );

        solver = new TokenReturnSolver();
    }

    function test_IdleAssetsCanRebalanceOut() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory data = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            data
        );

        assertEq(vault.getAssetBreakdown().totalIdle, 50e9, "idle");
        assertEq(dv1.balanceOf(address(vault)), 50e9, "dvBal");
    }

    function test_CanRebalanceToIdle() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory outData = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            outData
        );

        bytes memory inData = solver.buildForIdleIn(vault, 25e9);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(vault),
                tokenIn: vault.asset(),
                amountIn: 25e9,
                destinationOut: address(dv1),
                tokenOut: address(dv1.underlyer()),
                amountOut: 25e9
            }),
            inData
        );

        assertEq(vault.getAssetBreakdown().totalIdle, 75e9, "idle");
        assertEq(dv1.balanceOf(address(vault)), 25e9, "dvBal");
    }

    function test_DebtValuesAreUpdated() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        assertEq(vault.getAssetBreakdown().totalDebt, 0, "predebt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 0, "premin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 0, "premax");

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory data = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 0.25e9, 0.75e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            data
        );

        assertEq(vault.getAssetBreakdown().totalDebt, 25e9, "debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 12.5e9, "min");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 37.5e9, "max");
    }

    function test_UpdatesSystemWideNavOps() public {
        // TODO: Move to an integration test

        // address user = makeAddr("user");
        // _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        // _mockSucessfulRebalance();

        // _depositFor(user, 100e9);

        // // Setup the solver data to mint us the dv1 underlying for amount
        // bytes memory data = solver.buildDataForDvIn(dv1, 50e9);
        // _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);

        // VerifyNavOpsInProgress checkSolver = new VerifyNavOpsInProgress();

        // address dvUnderlyer = address(dv1.underlyer());
        // address baseAsset = vault.asset();

        // vm.expectRevert(abi.encodeWithSelector(VerifyNavOpsInProgress.NavOpsInProgress.selector, abi.encode(1)));
        // vault.flashRebalance(
        //     checkSolver,
        //     IStrategy.RebalanceParams({
        //         destinationIn: address(dv1),
        //         tokenIn: dvUnderlyer,
        //         amountIn: 50e9,
        //         destinationOut: address(vault),
        //         tokenOut: baseAsset,
        //         amountOut: 50e9
        //     }),
        //     abi.encode(address(systemSecurity))
        // );
    }

    function test_NavPerShareIncreaseNotRealizedImmediately() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        vault.setProfitUnlockPeriod(86_400);

        assertEq(vault.convertToShares(1e9), 1e9, "originalNavShare");
        assertEq(vault.totalAssets(), 100e9, "originalAssets");

        // We swap 50 idle for 150 assets at 1:1 value
        bytes memory data = solver.buildDataForDvIn(dv1, 150e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 150e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            data
        );

        // Immediately after rebalance, shares are still worth the same
        // event though we now have double the assets
        assertEq(vault.totalAssets(), 200e9, "immediateAfterAssets");
        assertEq(vault.convertToShares(1e9), 1e9, "immediateAfterNavShare");

        vm.warp(block.timestamp + 86_400);

        assertEq(vault.convertToShares(1e9), 0.5e9, "afterTimeShares");
        assertEq(vault.totalAssets(), 200e9, "afterTimeAssets");
    }

    function test_NavPerShareIncreasesWhenUnlockNotConfigured() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        vault.setProfitUnlockPeriod(0);

        assertEq(vault.convertToShares(1e9), 1e9, "originalNavShare");
        assertEq(vault.totalAssets(), 100e9, "originalAssets");

        // We swap 50 idle for 150 assets at 1:1 value
        bytes memory data = solver.buildDataForDvIn(dv1, 150e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 150e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            data
        );

        // Immediately after rebalance, shares are still worth the same
        // event though we now have double the assets
        assertEq(vault.totalAssets(), 200e9, "immediateAfterAssets");
        assertEq(vault.convertToShares(1e9), 0.5e9, "immediateAfterNavShare");
    }

    function test_NotifiesStrategyOfSuccess() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory data = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);

        address dv1Underlyer = address(dv1.underlyer());
        address asset = vault.asset();

        vm.expectCall(lmpStrategy, abi.encodeWithSelector(ILMPStrategy.rebalanceSuccessfullyExecuted.selector));
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: dv1Underlyer,
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: asset,
                amountOut: 50e9
            }),
            data
        );
    }

    function test_VaultIsNotAddedToQueues() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory outData = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            outData
        );

        assertEq(vault.isInDebtReportingQueue(address(vault)), false, "outDebt");
        assertEq(vault.isInWithdrawalQueue((address(vault))), false, "outWithdrawal");
        assertEq(vault.isInDebtReportingQueue(address(dv1)), true, "outDebtDv");
        assertEq(vault.isInWithdrawalQueue((address(dv1))), true, "outWithdrawalDv");

        bytes memory inData = solver.buildForIdleIn(vault, 25e9);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(vault),
                tokenIn: vault.asset(),
                amountIn: 25e9,
                destinationOut: address(dv1),
                tokenOut: address(dv1.underlyer()),
                amountOut: 25e9
            }),
            inData
        );

        assertEq(vault.isInDebtReportingQueue(address(vault)), false, "inDebt");
        assertEq(vault.isInWithdrawalQueue((address(vault))), false, "inWithdrawal");
        assertEq(vault.isInDebtReportingQueue(address(dv1)), true, "outDebtDv");
        assertEq(vault.isInWithdrawalQueue((address(dv1))), true, "outWithdrawalDv");
    }

    function test_DestinationRemovedFromQueuesWhenBalanceEmpty() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory outData = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            outData
        );

        bytes memory inData = solver.buildForIdleIn(vault, 49e9);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(vault),
                tokenIn: vault.asset(),
                amountIn: 49e9,
                destinationOut: address(dv1),
                tokenOut: address(dv1.underlyer()),
                amountOut: 49e9
            }),
            inData
        );

        assertEq(_isInList(vault.getDebtReportingQueue(), address(dv1)), true, "d1");
        assertEq(_isInList(vault.getWithdrawalQueue(), address(dv1)), true, "w1");

        inData = solver.buildForIdleIn(vault, 1e9);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(vault),
                tokenIn: vault.asset(),
                amountIn: 1e9,
                destinationOut: address(dv1),
                tokenOut: address(dv1.underlyer()),
                amountOut: 1e9
            }),
            inData
        );

        assertEq(_isInList(vault.getDebtReportingQueue(), address(dv1)), false, "d2");
        assertEq(_isInList(vault.getWithdrawalQueue(), address(dv1)), false, "w2");
    }

    function test_DestinationsAddedToEndOfDebtReportQueue() public {
        DestinationVaultFake[] memory dvs = _setupNDestinations(10);

        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        uint256[4] memory order = [uint256(4), 2, 7, 8];

        for (uint256 x = 0; x < order.length; x++) {
            // Setup the solver data to mint us the dv1 underlying for amount
            bytes memory outData = solver.buildDataForDvIn(dvs[order[x]], 1e9);
            _mockDestVaultRangePricesLP(address(dvs[order[x]]), 1e9, 1e9, true);
            vault.flashRebalance(
                solver,
                IStrategy.RebalanceParams({
                    destinationIn: address(dvs[order[x]]),
                    tokenIn: address(dvs[order[x]].underlyer()),
                    amountIn: 1e9,
                    destinationOut: address(vault),
                    tokenOut: vault.asset(),
                    amountOut: 1e9
                }),
                outData
            );
        }

        // Two were added during setup, and we just added 4 more
        address[] memory queue = vault.getDebtReportingQueue();
        assertEq(queue.length, 6, "len");
        assertEq(address(queue[2]), address(dvs[4]), "ix2");
        assertEq(address(queue[3]), address(dvs[2]), "ix3");
        assertEq(address(queue[4]), address(dvs[7]), "ix4");
        assertEq(address(queue[5]), address(dvs[8]), "ix5");
    }

    function test_OutDestinationAddedToHeadOfWithdrawQueue() public {
        DestinationVaultFake[] memory dvs = _setupNDestinations(10);

        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Fill in a bunch of destinations
        uint256[4] memory order = [uint256(4), 2, 7, 8];
        for (uint256 x = 0; x < order.length; x++) {
            // Setup the solver data to mint us the dv1 underlying for amount
            bytes memory outData = solver.buildDataForDvIn(dvs[order[x]], 1e9);
            _mockDestVaultRangePricesLP(address(dvs[order[x]]), 1e9, 1e9, true);
            vault.flashRebalance(
                solver,
                IStrategy.RebalanceParams({
                    destinationIn: address(dvs[order[x]]),
                    tokenIn: address(dvs[order[x]].underlyer()),
                    amountIn: 1e9,
                    destinationOut: address(vault),
                    tokenOut: vault.asset(),
                    amountOut: 1e9
                }),
                outData
            );
        }

        // Swap out of 2 and into 5
        bytes memory xData = solver.buildDataForDvIn(dvs[5], 1e9);
        _mockDestVaultRangePricesLP(address(dvs[5]), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dvs[5]),
                tokenIn: address(dvs[5].underlyer()),
                amountIn: 0.5e9,
                destinationOut: address(dvs[2]),
                tokenOut: address(dvs[2].underlyer()),
                amountOut: 0.5e9
            }),
            xData
        );

        address[] memory queue = vault.getWithdrawalQueue();
        assertEq(address(queue[0]), address(dvs[2]), "out");
    }

    function test_InDestinationAddedToTailOfWithdrawQueue() public {
        DestinationVaultFake[] memory dvs = _setupNDestinations(10);

        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Fill in a bunch of destinations
        uint256[4] memory order = [uint256(4), 2, 7, 8];
        for (uint256 x = 0; x < order.length; x++) {
            // Setup the solver data to mint us the dv1 underlying for amount
            bytes memory outData = solver.buildDataForDvIn(dvs[order[x]], 1e9);
            _mockDestVaultRangePricesLP(address(dvs[order[x]]), 1e9, 1e9, true);
            vault.flashRebalance(
                solver,
                IStrategy.RebalanceParams({
                    destinationIn: address(dvs[order[x]]),
                    tokenIn: address(dvs[order[x]].underlyer()),
                    amountIn: 1e9,
                    destinationOut: address(vault),
                    tokenOut: vault.asset(),
                    amountOut: 1e9
                }),
                outData
            );
        }

        // Swap out of 2 and into 5
        bytes memory xData = solver.buildDataForDvIn(dvs[5], 1e9);
        _mockDestVaultRangePricesLP(address(dvs[5]), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dvs[5]),
                tokenIn: address(dvs[5].underlyer()),
                amountIn: 0.5e9,
                destinationOut: address(dvs[2]),
                tokenOut: address(dvs[2].underlyer()),
                amountOut: 0.5e9
            }),
            xData
        );

        address[] memory queue = vault.getWithdrawalQueue();
        assertEq(address(queue[queue.length - 1]), address(dvs[5]), "in");
    }

    function test_RevertIf_ActiveDeployedDestinationsGreaterThanLimit() public {
        DestinationVaultFake[] memory dvs = _setupNDestinations(49);

        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Fill in a bunch of destinations
        for (uint256 x = 0; x < dvs.length - 1; x++) {
            // Setup the solver data to mint us the dv1 underlying for amount
            bytes memory outData = solver.buildDataForDvIn(dvs[x], 1e9);
            _mockDestVaultRangePricesLP(address(dvs[x]), 1e9, 1e9, true);
            vault.flashRebalance(
                solver,
                IStrategy.RebalanceParams({
                    destinationIn: address(dvs[x]),
                    tokenIn: address(dvs[x].underlyer()),
                    amountIn: 1e9,
                    destinationOut: address(vault),
                    tokenOut: vault.asset(),
                    amountOut: 1e9
                }),
                outData
            );
        }

        // Swap out of 2 and into 5
        bytes memory xData = solver.buildDataForDvIn(dvs[48], 1e9);
        _mockDestVaultRangePricesLP(address(dvs[48]), 1e9, 1e9, true);
        address inUnderlyer = address(dvs[48].underlyer());
        address baseAsset = address(vault.asset());

        vm.expectRevert(abi.encodeWithSelector(LMPDestinations.TooManyDeployedDestinations.selector));
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dvs[48]),
                tokenIn: inUnderlyer,
                amountIn: 1e9,
                destinationOut: address(vault),
                tokenOut: baseAsset,
                amountOut: 1e9
            }),
            xData
        );
    }

    function test_RevertIf_RebalanceToTheSameDestination() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockSucessfulRebalance();

        _depositFor(user, 100e9);

        // Setup the solver data to mint us the dv1 underlying for amount
        bytes memory outData = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            outData
        );

        // Idle to Idle
        address baseAsset = vault.asset();
        vm.expectRevert(abi.encodeWithSelector(LMPVault.RebalanceDestinationsMatch.selector, address(vault)));
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(vault),
                tokenIn: baseAsset,
                amountIn: 50e9,
                destinationOut: address(vault),
                tokenOut: baseAsset,
                amountOut: 50e9
            }),
            outData
        );

        // DV to DV
        outData = solver.buildDataForDvIn(dv1, 50e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        address dv1Underlyer = address(dv1.underlyer());

        vm.expectRevert(abi.encodeWithSelector(LMPVault.RebalanceDestinationsMatch.selector, address(dv1)));
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: dv1Underlyer,
                amountIn: 50e9,
                destinationOut: address(dv1),
                tokenOut: dv1Underlyer,
                amountOut: 50e9
            }),
            outData
        );
    }

    function test_RevertIf_Paused() public { }

    function test_RevertIf_NotCalledByRole() public { }

    function _setupNDestinations(uint256 n) internal returns (DestinationVaultFake[] memory ret) {
        ret = new DestinationVaultFake[](n);
        for (uint256 i = 0; i < n; i++) {
            ret[i] = _createAddDestinationVault(
                DVSetup({
                    lmpVault: vault,
                    dvSharesToLMP: 0e9,
                    valuePerShare: 1e9,
                    minDebtValue: 0e9,
                    maxDebtValue: 0e9,
                    lastDebtReportTimestamp: block.timestamp
                })
            );
        }
    }

    function _isInList(address[] memory list, address check) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; ++i) {
            if (list[i] == check) {
                return true;
            }
        }
        return false;
    }
}

contract UpdateDebtReportingTests is LMPVaultTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_NoUnderflowOnDebtDecreaseScenario() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, true);

        address user = makeAddr("user");

        DestinationVaultFake dv1 = _setupDestinationWithRewarder(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 10e18,
                maxDebtValue: 10e18,
                lastDebtReportTimestamp: block.timestamp
            }),
            0
        );

        _depositFor(user, 1_000_000_000_000_000_010);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        _mockDestVaultRangePricesLP(address(dv1), 1.1e18, 1.1e18, true);

        vault.updateDebtReporting(1);

        vm.prank(user);
        vault.redeem(100_000_000_000_000_001, user, user);

        // Just don't revert
        vault.updateDebtReporting(1);
    }

    function test_EarnedAutoCompoundsAreFactoredIntoIdle() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, true);

        address user = makeAddr("user");

        DestinationVaultFake dv1 = _setupDestinationWithRewarder(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 10e18,
                maxDebtValue: 10e18,
                lastDebtReportTimestamp: block.timestamp
            }),
            10e18
        );

        DestinationVaultFake dv2 = _setupDestinationWithRewarder(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e18,
                valuePerShare: 1e18,
                minDebtValue: 10e18,
                maxDebtValue: 10e18,
                lastDebtReportTimestamp: block.timestamp
            }),
            9e18
        );

        _depositFor(user, 1_000_000_000_000_000_010);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        _mockDestVaultRangePricesLP(address(dv1), 1e18, 1e18, true);
        _mockDestVaultRangePricesLP(address(dv2), 1e18, 1e18, true);

        // We only have 2 destinations, just checking for re-processing
        vault.updateDebtReporting(4);

        // Idle was zero before we debt reporting
        // Dv1 gave us 10, 2 gave us 9
        assertEq(vault.getAssetBreakdown().totalIdle, 19e18, "idle");
    }

    function test_BurnedSharesViaWithdrawReduceTotals() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, true);

        address user = makeAddr("user");

        _depositFor(user, 10e9);

        DestinationVaultFake dv1 = _setupDestinationWithRewarder(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 10e9,
                valuePerShare: 1e9,
                minDebtValue: 9e9,
                maxDebtValue: 11e9,
                lastDebtReportTimestamp: block.timestamp
            }),
            0
        );

        DestinationVaultFake dv2 = _setupDestinationWithRewarder(
            DVSetup({
                lmpVault: vault,
                dvSharesToLMP: 5e9,
                valuePerShare: 1e9,
                minDebtValue: 4.5e9,
                maxDebtValue: 5.5e9,
                lastDebtReportTimestamp: block.timestamp
            }),
            0
        );

        _mockDestVaultRangePricesLP(address(dv1), 0.9e9, 1.1e9, true);
        _mockDestVaultRangePricesLP(address(dv2), 0.9e9, 1.1e9, true);

        // Everything from idle was rebalanced out
        vault.setTotalIdle(0);

        // At this point the user has deposited 10, and we've rebalanced
        // into two destinations that have a value of 20 total

        assertEq(vault.getAssetBreakdown().totalIdle, 0, "stage1Idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 15e9, "stage1Debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 13.5e9, "stage1DebtMin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 16.5e9, "stage1DebtMax");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 10e9, "stage1Dv1Debt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 9e9, "stage1Dv1MinDebt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 11e9, "stage1Dv1MaxDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 5e9, "stage1Dv2Debt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 4.5e9, "stage1Dv2MinDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 5.5e9, "stage1Dv2MaxDebt");

        // We only have 2 destinations, just checking for re-processing
        // We should see no change here
        vault.updateDebtReporting(4);

        // We should see no change in debt at this point
        assertEq(vault.getAssetBreakdown().totalIdle, 0, "stage2Idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 15e9, "stage2Debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 13.5e9, "stage2DebtMin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 16.5e9, "stage2DebtMax");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 10e9, "stage2Dv1Debt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 9e9, "stage2Dv1MinDebt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 11e9, "stage2Dv1MaxDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 5e9, "stage2Dv2Debt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 4.5e9, "stage2Dv2MinDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 5.5e9, "stage2Dv2MaxDebt");

        // Withdraw half
        vm.prank(user);
        vault.redeem(5e9, user, user);

        // We should see that totals have been updated, half gone, but the individual destination info
        // is still lagging. Based on totalMinDebt, half of the shares were worth 6.75
        // That means we tried to pull 6.75 value with dv shares that were worth .9 a piece
        // and so we burnt 7.5 shares. Those shares are actually worth 1 a piece so the extra
        // .75 drops into idle

        assertEq(vault.getAssetBreakdown().totalIdle, 0.75e9, "stage3Idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 7.5e9, "stage3Debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 6.75e9, "stage3DebtMin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 8.25e9, "stage3DebtMax");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 10e9, "stage3Dv1Debt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 9e9, "stage3Dv1MinDebt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 11e9, "stage3Dv1MaxDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 5e9, "stage3Dv2Debt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 4.5e9, "stage3Dv2MinDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 5.5e9, "stage3Dv2MaxDebt");

        vault.updateDebtReporting(4);

        // We should see no change in idle or debt totals, but dv1 caches updated
        // We burned 75% of the shares with no change in price so the cached
        // numbers should go down by 75%
        assertEq(vault.getAssetBreakdown().totalIdle, 0.75e9, "stage4Idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 7.5e9, "stage4Debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 6.75e9, "stage4DebtMin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 8.25e9, "stage4DebtMax");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 2.5e9, "stage4Dv1Debt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 2.25e9, "stage4Dv1MinDebt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 2.75e9, "stage4Dv1MaxDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 5e9, "stage4Dv2Debt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 4.5e9, "stage4Dv2MinDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 5.5e9, "stage4Dv2MaxDebt");

        vm.startPrank(user);
        vault.redeem(4e9, user, user);
        vm.stopPrank();

        // Total asset are currently worth 7.5 on withdraw (.75 + 6.75) and we burned 80% of the shares
        // so we tried to get 6 assets. .75 came from idle. 5.25 left. Burned everthing in dv1 and
        // received 2.5. 2.75 left. DV2 min value is 4.5 so we have to burn 61.11% to cover.
        // DV2 has 5 shares so we burn 3.055 of them. They're worth 1:1 so we pulled an
        // extra 0.3055 which drops into idle. Cached values don't change, only totals
        assertEq(vault.getAssetBreakdown().totalIdle, 0.305555555e9, "stage5Idle");
        assertEq(vault.getAssetBreakdown().totalDebt, 1.944444445e9, "stage5Debt");
        assertEq(vault.getAssetBreakdown().totalDebtMin, 1.75e9, "stage5DebtMin");
        assertEq(vault.getAssetBreakdown().totalDebtMax, 2.138888889e9, "stage5DebtMax");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 2.5e9, "stage5Dv1Debt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 2.25e9, "stage5Dv1MinDebt");
        assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 2.75e9, "stage5Dv1MaxDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 5e9, "stage5Dv2Debt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 4.5e9, "stage5Dv2MinDebt");
        assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 5.5e9, "stage5Dv2MaxDebt");

        // TODO: Revisit

        // // Double the price of DV2 to ensure its picked up when combined with a share deduction
        // _mockDestVaultRangePricesLP(address(dv2), 0.9e9 * 2, 1.1e9 * 2, true);
        // vault.updateDebtReporting(4);

        // // Reflect exhausted DV1 and updated cached DV2
        // assertEq(vault.getAssetBreakdown().totalIdle, 0.305555555e9, "stage6Idle");
        // assertEq(vault.getAssetBreakdown().totalDebt, 1.944444445e9 * 2, "stage6Debt");
        // assertEq(vault.getAssetBreakdown().totalDebtMin, 1.75e9 * 2, "stage6DebtMin");
        // assertEq(vault.getAssetBreakdown().totalDebtMax, 2.138888889e9 * 2, "stage6DebtMax");
        // assertEq(vault.getDestinationInfo(address(dv1)).cachedDebtValue, 0, "stage6Dv1Debt");
        // assertEq(vault.getDestinationInfo(address(dv1)).cachedMinDebtValue, 0, "stage6Dv1MinDebt");
        // assertEq(vault.getDestinationInfo(address(dv1)).cachedMaxDebtValue, 0, "stage6Dv1MaxDebt");
        // assertEq(vault.getDestinationInfo(address(dv2)).cachedDebtValue, 1.944444445e9 * 2, "stage6Dv2Debt");
        // assertEq(vault.getDestinationInfo(address(dv2)).cachedMinDebtValue, 1.75e9 * 2, "stage6Dv2MinDebt");
        // assertEq(vault.getDestinationInfo(address(dv2)).cachedMaxDebtValue, 2.138888889e9 * 2, "stage6Dv2MaxDebt");
    }

    function _setupDestinationWithRewarder(
        DVSetup memory setup,
        uint256 amount
    ) internal returns (DestinationVaultFake dv1) {
        dv1 = _setupDestinationVault(setup);
        FakeDestinationRewarder dv1Rewarder = new FakeDestinationRewarder(vaultAsset);
        vm.mockCall(
            address(dv1), abi.encodeWithSelector(IDestinationVault.rewarder.selector), abi.encode(address(dv1Rewarder))
        );
        dv1Rewarder.claimAmountOnNextCall(amount);
        return dv1;
    }
}

// Testing previewWithdraw / previewRedeem / maxWithdraw
contract PreviewTests is FlashRebalanceTests {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_previewWithdraw() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 sharesMinted = _depositFor(user, depositAmount);

        uint256 previewShares = vault.previewWithdraw(depositAmount);

        // Comparing shares minted to shares expected to be burned when withdrawing full deposit amount.  Should be
        //    equal to mint with no other actions happening in the vault at this point.
        assertEq(sharesMinted, previewShares);

        previewShares = vault.previewWithdraw(6e18);

        // 1:1 right now, asset amount of 6e18 should yield same number of shares.
        assertEq(6e18, previewShares);
    }

    function test_previewWithdraw_MakesNoStateChanges() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        _depositFor(user, depositAmount);

        vm.startStateDiffRecording();

        vault.previewWithdraw(depositAmount);

        VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        _ensureNoStateChanges(records);
    }

    // Just testing this functionality in a situation where shares are not minting 1:1
    function test_previewWithdraw_NavChange() public {
        _flashRebalance();

        // Check to make sure that assets and shares are no longer 1:1
        assertEq(vault.convertToShares(1e9), 0.5e9, "immediateAfterNavShare");

        uint256 previewShares = vault.previewWithdraw(45e9);

        // Nav / share currently 2
        assertEq(previewShares, 45e9 / 2);
    }

    function test_previewRedeem() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 sharesMinted = _depositFor(user, depositAmount);

        uint256 previewAssets = vault.previewRedeem(sharesMinted);

        // Comparing amount deposited to amount expected to be returned.
        assertEq(depositAmount, previewAssets);

        previewAssets = vault.previewRedeem(4e9);

        // 1:1 right now, 4e9 shares should yield same in assets.
        assertEq(4e9, previewAssets);
    }

    function test_previewRedeem_MakesNoStateChanges() public {
        address user = makeAddr("user1");
        uint256 depositAmount = 9e18;
        uint256 sharesMinted = _depositFor(user, depositAmount);

        vm.startStateDiffRecording();

        vault.previewRedeem(sharesMinted);

        VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();
        _ensureNoStateChanges(records);
    }

    // Just testing this functionality in a situation where shares are not minting 1:1
    function test_previewRedeem_NavChange() public {
        _flashRebalance();

        // Check to make sure that assets and shares are no longer 1:1
        assertEq(vault.convertToShares(1e9), 0.5e9, "immediateAfterNavShare");

        uint256 previewAssets = vault.previewRedeem(20e9);

        // Nav / share currently 2
        assertEq(previewAssets, 20e9 * 2);
    }

    function test_maxWithdraw_Returns0_WhenVaultPaused() public {
        address user = makeAddr("user");
        _mockAccessControllerHasRole(accessController, address(this), Roles.EMERGENCY_PAUSER, true);
        _depositFor(user, 9e18);

        assertGt(vault.balanceOf(user), 0);

        vault.pause();

        uint256 maxWithdrawableAssets = vault.maxWithdraw(user);
        assertEq(0, maxWithdrawableAssets);
    }

    function test_maxWithdraw_Returns0_WhenOwnerHasNoBalance() public {
        address user1 = makeAddr("user1");

        assertEq(vault.balanceOf(user1), 0);

        assertEq(vault.maxWithdraw(user1), 0);
    }

    function test_maxWithdraw_ReturnsCorrectAmount() public {
        uint256 depositAmount = 9e18;
        address user = makeAddr("user");
        _depositFor(user, depositAmount);

        // vault reporting 1:1.
        assertEq(vault.balanceOf(user), depositAmount);

        uint256 maxWithdrawableAssets = vault.maxWithdraw(user);
        assertEq(depositAmount, maxWithdrawableAssets);
    }

    function _flashRebalance() private {
        address user = makeAddr("user");
        uint256 depositAmount = 100e9;

        _mockAccessControllerHasRole(accessController, address(this), Roles.SOLVER_ROLE, true);
        _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);
        _mockSucessfulRebalance();

        _depositFor(user, depositAmount);

        vault.setProfitUnlockPeriod(0);

        // Check that assets and shares 1:1
        assertEq(vault.convertToShares(1e9), 1e9, "originalNavShare");

        // We swap 50 idle for 150 assets at 1:1 value
        bytes memory data = solver.buildDataForDvIn(dv1, 150e9);
        _mockDestVaultRangePricesLP(address(dv1), 1e9, 1e9, true);
        vault.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationIn: address(dv1),
                tokenIn: address(dv1.underlyer()),
                amountIn: 150e9,
                destinationOut: address(vault),
                tokenOut: vault.asset(),
                amountOut: 50e9
            }),
            data
        );
    }

    function _ensureNoStateChanges(VmSafe.AccountAccess[] memory records) private {
        for (uint256 i = 0; i < records.length; i++) {
            if (!records[i].reverted) {
                assertEq(records[i].oldBalance, records[i].newBalance);
                assertEq(records[i].deployedCode.length, 0);

                for (uint256 s = 0; s < records[i].storageAccesses.length; s++) {
                    if (records[i].storageAccesses[s].isWrite) {
                        if (!records[i].storageAccesses[s].reverted) {
                            assertEq(
                                records[i].storageAccesses[s].previousValue, records[i].storageAccesses[s].newValue
                            );
                        }
                    }
                }
            }
        }
    }
}
/// =====================================================
/// Mock Contracts
/// =====================================================

contract DestinationVaultFake {
    TestERC20 public underlyer;
    TestERC20 public baseAsset;
    mapping(address => uint256) public balances;
    uint256 public valuePerShare;
    int256[] public baseAssetSlippages;

    constructor(TestERC20 _underlyer, TestERC20 _baseAsset) {
        underlyer = _underlyer;
        baseAsset = _baseAsset;
    }

    function decimals() external view returns (uint8) {
        return baseAsset.decimals();
    }

    function setDebtValuePerShare(uint256 _valuePerShare) external {
        valuePerShare = _valuePerShare;
    }

    function debtValue(uint256 shares) external view returns (uint256) {
        return shares * valuePerShare / 1e18;
    }

    function mint(uint256 vaultShares, address receiver) external {
        balances[receiver] += vaultShares;
    }

    function setWithdrawBaseAssetSlippage(int256 slippage) external {
        baseAssetSlippages.push(slippage);
    }

    function setWithdrawBaseAssetSlippage(int256 slippage1, int256 slippage2) external {
        baseAssetSlippages.push(slippage2);
        baseAssetSlippages.push(slippage1);
    }

    function setWithdrawBaseAssetSlippage(int256 slippage1, int256 slippage2, int256 slippage3) external {
        baseAssetSlippages.push(slippage3);
        baseAssetSlippages.push(slippage2);
        baseAssetSlippages.push(slippage1);
    }

    function setWithdrawBaseAssetSlippage(
        int256 slippage1,
        int256 slippage2,
        int256 slippage3,
        int256 slippage4
    ) external {
        baseAssetSlippages.push(slippage4);
        baseAssetSlippages.push(slippage3);
        baseAssetSlippages.push(slippage2);
        baseAssetSlippages.push(slippage1);
    }

    function withdrawBaseAsset(uint256 shares, address receiver) external returns (uint256 assets) {
        int256 baseAssetSlippage = 0;
        if (baseAssetSlippages.length > 0) {
            baseAssetSlippage = baseAssetSlippages[baseAssetSlippages.length - 1];
            baseAssetSlippages.pop();
        }
        assets = uint256(int256((shares * valuePerShare / 10 ** baseAsset.decimals())) - baseAssetSlippage);
        baseAsset.mint(receiver, assets);
        baseAssetSlippage = 0;
        balances[msg.sender] -= shares;
    }

    function balanceOf(address wallet) external view returns (uint256) {
        return balances[wallet];
    }

    function depositUnderlying(uint256 amount) external returns (uint256 shares) {
        underlyer.transferFrom(msg.sender, address(this), amount);
        console.log("depositUnderlying befre bal", balances[msg.sender]);
        balances[msg.sender] += amount;
        console.log("depositUnderlying after bal", balances[msg.sender]);
        shares = amount;
    }

    function withdrawUnderlying(uint256 shares, address to) external returns (uint256 amount) {
        amount = shares;
        balances[msg.sender] -= shares;
        console.log("withdrawUnderlying after bal", balances[msg.sender]);
        underlyer.transfer(to, amount);
    }
}

contract TestLMPVault is LMPVault {
    using WithdrawalQueue for StructuredLinkedList.List;
    using EnumerableSet for EnumerableSet.AddressSet;
    using AutoPoolToken for AutoPoolToken.TokenData;

    bool private _nextDepositGetsDoubleShares;
    bool private _nextWithdrawHalvesIdle;

    constructor(ISystemRegistry _systemRegistry, address _vaultAsset) LMPVault(_systemRegistry, _vaultAsset, false) { }

    function nextDepositGetsDoubleShares() public {
        _nextDepositGetsDoubleShares = true;
    }

    function setNextWithdrawHalvesIdle() public {
        _nextWithdrawHalvesIdle = true;
    }

    function totalIdle() public view returns (uint256) {
        return getAssetBreakdown().totalIdle;
    }

    function totalDebt() public view returns (uint256) {
        return getAssetBreakdown().totalDebt;
    }

    function totalDebtMin() public view returns (uint256) {
        return getAssetBreakdown().totalDebtMin;
    }

    function totalDebtMax() public view returns (uint256) {
        return getAssetBreakdown().totalDebtMax;
    }

    function _transferAndMint(uint256 assets, uint256 shares, address receiver) internal virtual override {
        super._transferAndMint(assets, _nextDepositGetsDoubleShares ? shares * 2 : shares, receiver);
        _nextDepositGetsDoubleShares = false;
    }

    function addToWithdrawalQueueHead(address destination) external virtual {
        _withdrawalQueue.addToHead(destination);
    }

    function addToWithdrawalQueueTail(address destination) external virtual {
        _withdrawalQueue.addToTail(destination);
    }

    function addToDebtReportingHead(address destination) external virtual {
        _debtReportQueue.addToHead(destination);
    }

    function addToDebtReportingTail(address destination) external virtual {
        _debtReportQueue.addToTail(destination);
    }

    function increaseTotalDebts(uint256 _totalDebt, uint256 _totalMinDebt, uint256 _totalMaxDebt) external virtual {
        _assetBreakdown.totalDebt += _totalDebt;
        _assetBreakdown.totalDebtMin += _totalMinDebt;
        _assetBreakdown.totalDebtMax += _totalMaxDebt;
    }

    function setTotalDebts(uint256 _totalDebt, uint256 _totalMinDebt, uint256 _totalMaxDebt) external virtual {
        _assetBreakdown.totalDebt = _totalDebt;
        _assetBreakdown.totalDebtMin = _totalMinDebt;
        _assetBreakdown.totalDebtMax = _totalMaxDebt;
    }

    function setTotalIdle(uint256 _totalIdle) external {
        _assetBreakdown.totalIdle = _totalIdle;
    }

    function setTotalDebt(uint256 _totalDebt) external {
        _assetBreakdown.totalDebt = _totalDebt;
    }

    function mint(address receiver, uint256 amount) public {
        _tokenData.mint(receiver, amount);
    }

    function setDestinationInfo(
        address destination,
        uint256 cachedDebtValue,
        uint256 cachedMinDebtValue,
        uint256 cachedMaxDebtValue,
        uint256 ownedShares,
        uint256 lastDebtReportTimestamp
    ) external {
        _destinationInfo[destination] = LMPDebt.DestinationInfo({
            cachedDebtValue: cachedDebtValue,
            cachedMinDebtValue: cachedMinDebtValue,
            cachedMaxDebtValue: cachedMaxDebtValue,
            ownedShares: ownedShares,
            lastReport: lastDebtReportTimestamp
        });

        _destinations.add(destination);
    }

    function convertToShares(uint256 assets, TotalAssetPurpose purpose) public view virtual returns (uint256 shares) {
        shares = convertToShares(assets, totalAssets(purpose), totalSupply(), Math.Rounding.Down);
    }

    function convertToAssets(
        uint256 shares,
        TotalAssetPurpose purpose
    ) external view virtual returns (uint256 assets) {
        assets = convertToAssets(shares, totalAssets(purpose), totalSupply(), Math.Rounding.Down);
    }

    function _completeWithdrawal(
        uint256 assets,
        uint256 shares,
        address owner,
        address receiver
    ) internal virtual override {
        if (_nextWithdrawHalvesIdle) {
            _assetBreakdown.totalIdle /= 2;
            _nextWithdrawHalvesIdle = false;
        }
        super._completeWithdrawal(assets, shares, owner, receiver);
    }
}

contract FeeAndProfitTestVault is TestLMPVault {
    using WithdrawalQueue for StructuredLinkedList.List;

    uint256 private _feeSharesToBeCollected;
    bool private _useRealCollectFees;

    constructor(ISystemRegistry _systemRegistry, address _vaultAsset) TestLMPVault(_systemRegistry, _vaultAsset) { }

    function useRealCollectFees() public {
        _useRealCollectFees = true;
    }

    function feesAndProfitHandling(uint256 newIdle, uint256 newDebt, uint256 startingTotalAssets) public {
        _feeAndProfitHandling(newIdle + newDebt, startingTotalAssets, true);
    }

    function setUnlockPeriodInSeconds(uint48 unlockPeriod) public {
        _profitUnlockSettings.unlockPeriodInSeconds = unlockPeriod;
    }

    function setLastProfitUnlockTime(uint256 lastUnlockTime) public {
        _profitUnlockSettings.lastProfitUnlockTime = uint48(lastUnlockTime);
    }

    function isInDebtReportingQueue(address check) public view returns (bool) {
        return _debtReportQueue.addressExists(check);
    }

    function isInWithdrawalQueue(address check) public view returns (bool) {
        return _withdrawalQueue.addressExists(check);
    }

    function setProfitUnlockRate(uint256 unlockRate) public {
        _profitUnlockSettings.profitUnlockRate = unlockRate;
    }

    function setFeeSharesToBeCollected(uint256 shares) public {
        _feeSharesToBeCollected = shares;
    }

    function setFullProfitUnlockTime(uint256 time) public {
        _profitUnlockSettings.fullProfitUnlockTime = uint48(time);
    }

    function _collectFees(
        uint256 x,
        uint256 currentTotalSupply,
        bool collectPeriodicFees
    ) internal virtual override returns (uint256) {
        if (_useRealCollectFees) {
            return super._collectFees(x, currentTotalSupply, collectPeriodicFees);
        } else {
            uint256 shares = _feeSharesToBeCollected;
            _feeSharesToBeCollected = 0;

            mint(address(4335), shares);

            return currentTotalSupply + shares;
        }
    }
}

contract TokenReturnSolver is IERC3156FlashBorrower {
    constructor() { }

    function buildDataForDvIn(DestinationVaultFake dv, uint256 returnAmount) public view returns (bytes memory) {
        return abi.encode(returnAmount, dv.underlyer());
    }

    function buildForIdleIn(LMPVault vault, uint256 returnAmount) public view returns (bytes memory) {
        return abi.encode(returnAmount, vault.asset());
    }

    function onFlashLoan(address, address, uint256, uint256, bytes memory data) external returns (bytes32) {
        (uint256 ret, address token) = abi.decode(data, (uint256, address));

        TestERC20(token).mint(msg.sender, ret);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FakeDestinationRewarder {
    TestERC20 internal _baseAsset;
    uint256 internal _claimAmountOnNextCall;

    constructor(TestERC20 baseAsset_) {
        _baseAsset = baseAsset_;
    }

    function claimAmountOnNextCall(uint256 amount) public {
        _claimAmountOnNextCall = amount;
    }

    function getReward(address, bool) public {
        if (_claimAmountOnNextCall > 0) {
            _baseAsset.mint(msg.sender, _claimAmountOnNextCall);
        }
    }
}
