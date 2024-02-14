// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count,var-name-mixedcase

import { Roles } from "src/libs/Roles.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { Errors } from "src/utils/Errors.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { DestinationVaultMocks } from "test/unit/mocks/DestinationVaultMocks.t.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
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

contract LMPVaultTests is
    Test,
    TestBase,
    SystemRegistryMocks,
    SystemSecurityMocks,
    DestinationVaultMocks,
    AccessControllerMocks
{
    address internal FEE_RECIPIENT = address(4335);

    constructor()
        TestBase(vm)
        SystemRegistryMocks(vm)
        SystemSecurityMocks(vm)
        DestinationVaultMocks(vm)
        AccessControllerMocks(vm)
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

    event PerformanceFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event NewTotalAssetsHighWatermark(uint256 assets, uint256 timestamp);
    event TotalSupplyLimitSet(uint256 limit);
    event PerWalletLimitSet(uint256 limit);
    event SymbolAndDescSet(string symbol, string desc);
    event ManagementFeeSet(uint256 newFee);
    event PendingManagementFeeSet(uint256 pendingManagementFeeBps);
    event ManagementFeeSinkSet(address newManagementFeeSink);
    event NextManagementFeeTakeSet(uint256 nextManagementFeeTake);
    event RebalanceFeeHighWaterMarkEnabledSet(bool enabled);
    event TokensPulled(address[] tokens, uint256[] amounts, address[] destinations);
    event TokensRecovered(address[] tokens, uint256[] amounts, address[] destinations);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event RewarderSet(address rewarder);
    event DestinationDebtReporting(
        address destination, LMPDebt.IdleDebtUpdates debtInfo, uint256 claimed, uint256 claimGasUsed
    );
    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 idle, uint256 debt);
    event ManagementFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Shutdown(ILMPVault.VaultShutdownStatus reason);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public virtual {
        vm.warp(1_702_419_857);
        systemRegistry = ISystemRegistry(newAddr(1, "systemRegistry"));

        accessController = IAccessController(newAddr(2, "accessController"));
        _mockSysRegAccessController(systemRegistry, address(accessController));

        systemSecurity = ISystemSecurity(newAddr(3, "systemSecurity"));
        _mockSysRegSystemSecurity(systemRegistry, address(systemSecurity));
        _mockSysSecurityInit(systemSecurity);

        vaultAsset = new TestERC20("mockWETH", "Mock WETH");
        vaultAsset.setDecimals(9);
        vm.label(address(vaultAsset), "baseAsset");

        lmpStrategy = newAddr(4, "lmpStrategy");
        bytes memory initData = abi.encode("");

        FeeAndProfitTestVault tempVault = new FeeAndProfitTestVault(systemRegistry, address(vaultAsset));
        vault = FeeAndProfitTestVault(Clones.cloneDeterministic(address(tempVault), "salt1"));
        vault.initialize(type(uint112).max, type(uint112).max, lmpStrategy, "1", "1", initData);
        vm.label(address(vault), "FeeAndProfitTestVaultProxy");
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
        sharesReceived = vault.deposit(amount, user);
    }

    function _mintFor(address user, uint256 assetAmount, uint256 shareAmount) internal returns (uint256 assetsTaken) {
        vaultAsset.mint(address(this), assetAmount);
        vaultAsset.approve(address(vault), assetAmount);
        assetsTaken = vault.mint(shareAmount, user);
    }

    function _setupDestinationVault(DVSetup memory setup) internal returns (DestinationVaultFake dv) {
        // Create the destination vault
        TestERC20 dvToken = new TestERC20("DV", "DV");
        dvToken.setDecimals(9);
        dv = new DestinationVaultFake(dvToken, TestERC20(setup.lmpVault.asset()));

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

        // We have our debt reporting snapshot
        setup.lmpVault.setDestinationInfo(
            address(dv),
            (setup.minDebtValue + setup.maxDebtValue) / 2,
            setup.minDebtValue,
            setup.maxDebtValue,
            setup.dvSharesToLMP,
            setup.lastDebtReportTimestamp
        );

        return dv;
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

    function test_setPerformanceFeeBps_RevertIf_CallerMissingFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_FEE_SETTER_ROLE, false);

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setPerformanceFeeBps(100);
        vm.stopPrank();

        vault.setPerformanceFeeBps(100);
    }

    function test_setManagementFeeSink_RevertIf_CallerMissingMgmtFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, false);

        address feeSink = makeAddr("feeSink");

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setManagementFeeSink(feeSink);
        vm.stopPrank();

        vault.setManagementFeeSink(feeSink);
    }

    function test_setManagementFeeBps_RevertIf_CallerMissingMgmtFeeSetterRole() public {
        // This test is allowed
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, true);

        // notAdmin is not allowed
        address notAdmin = makeAddr("notAdmin");
        _mockAccessControllerHasRole(accessController, notAdmin, Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, false);

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        vault.setManagementFeeBps(100);
        vm.stopPrank();

        vault.setManagementFeeBps(100);
    }

    function test_setManagementFeeBps_RevertIf_FeeIsGreaterThanTenPercent() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, true);

        vm.expectRevert(abi.encodeWithSelector(LMPVault.InvalidFee.selector, 1001));
        vault.setManagementFeeBps(1001);

        vault.setManagementFeeBps(1000);
    }

    function test_setManagementFeeSink_SetsAndEmitsAddress() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE, true);

        address runOne = makeAddr("runOne");
        vm.expectEmit(false, false, false, true);
        emit ManagementFeeSinkSet(runOne);
        vault.setManagementFeeSink(runOne);

        assertEq(vault.getFeeSettings().managementFeeSink, runOne, "setRunOne");

        address runTwo = address(0);
        vm.expectEmit(false, false, false, true);
        emit ManagementFeeSinkSet(runTwo);
        vault.setManagementFeeSink(runTwo);

        assertEq(vault.getFeeSettings().managementFeeSink, runTwo, "setRunOne");
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
        address user = newAddr(1001, "user1");
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
        address user = newAddr(1001, "user1");
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
        address user = newAddr(1001, "user1");
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
        vault.increaseTotalDebts(100e18, 100e18, 100e18);

        // Too small rounded to 0
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "shares"));
        vault.deposit(1, address(this));

        // But a larger amount still goes in
        uint256 shares = vault.deposit(1000, address(this));
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
        address user = newAddr(1001, "user1");
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

    function test_Loop2() public {
        uint256 multi = 10;

        address user = newAddr(1001, "user1");
        uint256 userInitialDeposit = 1 * multi;
        _depositFor(user, userInitialDeposit);

        uint256 newIdle = 2 * multi;
        vault.setTotalIdle(newIdle);
        vaultAsset.mint(address(vault), newIdle);

        vm.prank(user);
        vault.redeem(userInitialDeposit - 1, user, user);

        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());
    }

    function test_Loop() public {
        uint256 multi = 1;

        address user = newAddr(1001, "user1");
        _depositFor(user, 10 * multi);
        vault.setTotalIdle(12_000_000 * multi);
        vaultAsset.mint(address(vault), 12_000_000 * multi);

        uint256 totalDeposited = 1 * multi;
        uint256 totalWithdrawn = 0;

        for (uint256 i = 0; i < 60; i++) {
            uint256 totalAssets = vault.totalAssets();
            _depositFor(user, 2 * totalAssets - 1);
            totalDeposited += 2 * totalAssets - 1;
            vm.prank(user);
            vault.withdraw(1 * multi, user, user);
            totalWithdrawn += 1 * multi;
        }

        console.log("user1 totalDeposited", totalDeposited - totalWithdrawn);

        address user2 = newAddr(1002, "user2");
        uint256 user2Deposit = 2 * vault.totalAssets() - 1;
        _depositFor(user2, user2Deposit);

        uint256 user1Bal = vault.balanceOf(user);
        vm.prank(user);
        uint256 user1Remove = vault.redeem(user1Bal, user, user);
        console.log("user1 removed       ", user1Remove);

        console.log("user2 totalDeposited", user2Deposit);

        uint256 user2Bal = vault.balanceOf(user2);
        vm.prank(user2);
        uint256 user2Remove = vault.redeem(user2Bal, user2, user2);
        console.log("user2 removed       ", user2Remove);

        console.log("endingTotalAssets", vault.totalAssets());
        console.log("endingBalance", vaultAsset.balanceOf(address(vault)));
    }

    // TODO: Finish mimicking the Deposit tests
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

    function test_RevertIf_BaseAssetIsAttempted() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory destinations = new address[](1);

        tokens[0] = address(vaultAsset);
        amounts[0] = 1e18;
        destinations[0] = address(this);

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowed.selector, address(vaultAsset)));
        vault.recover(tokens, amounts, destinations);
    }

    function test_RevertIf_DestinationVaultIsAttempted() public {
        _mockAccessControllerHasRole(accessController, address(this), Roles.TOKEN_RECOVERY_ROLE, true);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory destinations = new address[](1);

        address dv = address(
            _setupDestinationVault(
                DVSetup({
                    lmpVault: vault,
                    dvSharesToLMP: 10e18,
                    valuePerShare: 1e18,
                    minDebtValue: 5e18,
                    maxDebtValue: 15e18,
                    lastDebtReportTimestamp: block.timestamp
                })
            )
        );

        tokens[0] = address(dv);
        amounts[0] = 1e18;
        destinations[0] = address(this);

        assertEq(vault.isDestinationRegistered(dv), true, "destinationRegistered");

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowed.selector, dv));
        vault.recover(tokens, amounts, destinations);
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

// contract SetTotalSupplyLimitTests is LMPVaultTests {
//     function setUp() public virtual override {
//         super.setUp();
//     }

//     function test_EmitsEvent() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vm.expectEmit(true, true, true, true);
//         emit TotalSupplyLimitSet(vault.ONE_UNIT());
//         vault.setTotalSupplyLimit(vault.ONE_UNIT());
//     }

//     function test_AllowsZeroValue() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vault.setTotalSupplyLimit(vault.ONE_UNIT());
//         vault.setTotalSupplyLimit(0);
//     }

//     function test_SavesValidValue() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 newValue = vault.ONE_UNIT() * 35;
//         assertFalse(newValue == vault.totalSupplyLimit(), "valuesEqual");

//         vault.setTotalSupplyLimit(newValue);

//         assertEq(newValue, vault.totalSupplyLimit());
//     }

//     function test_RevertIf_OverLimit() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vault.setTotalSupplyLimit(vault.ONE_UNIT());
//         uint256 originalLimit = vault.totalSupplyLimit();
//         uint256 maxLimit = vault.MAX_LIMIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.TotalSupplyOverLimit.selector));
//         vault.setTotalSupplyLimit(maxLimit + 1);

//         vault.setTotalSupplyLimit(maxLimit);

//         assertEq(originalLimit, vault.ONE_UNIT(), "original");
//         assertEq(vault.totalSupplyLimit(), maxLimit, "newLimit");
//     }

//     function test_RevertIf_NotCalledByOwner() public {
//         address testUser = makeAddr("testUser");
//         _mockAccessControllerHasRole(accessController, testUser, Roles.AUTO_POOL_ADMIN, false);

//         uint256 oneUnit = vault.ONE_UNIT();

//         vm.startPrank(testUser);
//         vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
//         vault.setTotalSupplyLimit(oneUnit);
//         vm.stopPrank();

//         _mockAccessControllerHasRole(accessController, testUser, Roles.AUTO_POOL_ADMIN, true);

//         vm.startPrank(testUser);
//         vault.setTotalSupplyLimit(oneUnit);
//         vm.stopPrank();
//     }

//     function test_RevertIf_ValueIsLessThanOneUnit() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 oneUnit = vault.ONE_UNIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.TotalSupplyUnderLimit.selector));
//         vault.setTotalSupplyLimit(oneUnit - 1);

//         vault.setTotalSupplyLimit(oneUnit);
//     }

//     function test_RevertIf_ValueHasAnyPrecision() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 oneUnit = vault.ONE_UNIT();
//         uint256 maxValue = vault.MAX_LIMIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.InvalidLimit.selector));
//         vault.setTotalSupplyLimit(oneUnit + 1);

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.InvalidLimit.selector));
//         vault.setTotalSupplyLimit(maxValue - 1);

//         vault.setTotalSupplyLimit(oneUnit);
//         vault.setTotalSupplyLimit(maxValue);
//     }
// }

// contract SetPerWalletLimitTests is LMPVaultTests {
//     function setUp() public virtual override {
//         super.setUp();
//     }

//     function test_EmitsEvent() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vm.expectEmit(true, true, true, true);
//         emit PerWalletLimitSet(vault.ONE_UNIT());
//         vault.setPerWalletLimit(vault.ONE_UNIT());
//     }

//     function test_SavesValidValue() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 newValue = vault.ONE_UNIT() * 35;
//         assertFalse(newValue == vault.perWalletLimit(), "valuesEqual");

//         vault.setPerWalletLimit(newValue);

//         assertEq(newValue, vault.perWalletLimit());
//     }

//     function test_RevertIf_ValueIsZero() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "newWalletLimit"));
//         vault.setPerWalletLimit(0);
//     }

//     function test_RevertIf_OverLimit() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         vault.setPerWalletLimit(vault.ONE_UNIT());
//         uint256 originalLimit = vault.perWalletLimit();
//         uint256 maxLimit = vault.MAX_LIMIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.PerWalletOverLimit.selector));
//         vault.setPerWalletLimit(maxLimit + 1);

//         vault.setPerWalletLimit(maxLimit);

//         assertEq(originalLimit, vault.ONE_UNIT(), "original");
//         assertEq(vault.perWalletLimit(), maxLimit, "newLimit");
//     }

//     function test_RevertIf_NotCalledByOwner() public {
//         address testUser = makeAddr("testUser");
//         _mockAccessControllerHasRole(accessController, testUser, Roles.AUTO_POOL_ADMIN, false);

//         uint256 oneUnit = vault.ONE_UNIT();

//         vm.startPrank(testUser);
//         vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
//         vault.setPerWalletLimit(oneUnit);
//         vm.stopPrank();

//         _mockAccessControllerHasRole(accessController, testUser, Roles.AUTO_POOL_ADMIN, true);

//         vm.startPrank(testUser);
//         vault.setPerWalletLimit(oneUnit);
//         vm.stopPrank();
//     }

//     function test_RevertIf_ValueIsLessThanOneUnit() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 oneUnit = vault.ONE_UNIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.PerWalletUnderLimit.selector));
//         vault.setPerWalletLimit(oneUnit - 1);

//         vault.setPerWalletLimit(oneUnit);
//     }

//     function test_RevertIf_ValueHasAnyPrecision() public {
//         _mockAccessControllerHasRole(accessController, address(this), Roles.AUTO_POOL_ADMIN, true);

//         uint256 oneUnit = vault.ONE_UNIT();
//         uint256 maxValue = vault.MAX_LIMIT();

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.InvalidLimit.selector));
//         vault.setPerWalletLimit(oneUnit + 1);

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.InvalidLimit.selector));
//         vault.setPerWalletLimit(maxValue - 1);

//         vault.setPerWalletLimit(oneUnit);
//         vault.setPerWalletLimit(maxValue);
//     }
// }

contract RedeemTests is LMPVaultTests {
    using WithdrawalQueue for StructuredLinkedList.List;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_IdleAssetsUsedWhenAvailable() public {
        address user = newAddr(1001, "user1");
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
        address user = newAddr(1001, "user1");
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
        address user = newAddr(1001, "user1");
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

        dv1.setWithdrawBaseAssetSlippage(0.1e18);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);

        // They were worth 10 but we experienced .1 slippage
        assertEq(assetsReceived, 9.9e18, "assetsReceived");

        // We should have cleared everything since we burned all shares
        assertEq(vault.totalIdle(), 0, "totalIdle");
        assertEq(vault.totalDebt(), 0, "totalDebt");
        assertEq(vault.totalDebtMin(), 0, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 0, "totalDebtMax");
    }

    function test_PartiallyDecreasesDebtNumbers() public {
        address user = newAddr(1001, "user1");
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

        dv1.setWithdrawBaseAssetSlippage(0.1e18);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares / 2, user, user);

        // They were worth 5, 10 total but we burned half shares, and we experienced .1 slippage
        assertEq(assetsReceived, 4.9e18, "assetsReceived");

        // We should have cleared everything since we burned all shares
        assertEq(vault.totalIdle(), 0, "totalIdle");

        assertEq(vault.totalDebt(), 5e18, "totalDebt");
        assertEq(vault.totalDebtMin(), 4.995e18, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 5.005e18, "totalDebtMax");
    }

    function test_PositiveSlippageDropsIntoIdle() public {
        address user = newAddr(1001, "user1");
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

        dv1.setWithdrawBaseAssetSlippage(-1e18);

        vm.prank(user);
        uint256 assetsReceived = vault.redeem(userShares / 2, user, user);

        // They were worth 4.995, 9.99 (minDebt) total but we burned half shares
        assertEq(assetsReceived, 4.995e18, "assetsReceived");

        // We received positive slippage, so into idle it goes
        // And minor difference in minDebt and actual .005 goes into idle as well
        assertEq(vault.totalIdle(), 1.005e18, "totalIdle");

        assertEq(vault.totalDebt(), 5e18, "totalDebt");
        assertEq(vault.totalDebtMin(), 4.995e18, "totalDebtMin");
        assertEq(vault.totalDebtMax(), 5.005e18, "totalDebtMax");
    }

    function test_ExhaustedDestinationsAreRemovedFromWithdrawalQueue() public {
        address user = newAddr(1001, "user1");
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
            newLockShares * vault.MAX_BPS_PROFIT() / 77_865,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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
                currentProfitUnlockRate: 10e18 * vault.MAX_BPS_PROFIT() / 1 days,
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

contract DestinationVaultFake {
    TestERC20 public underlyer;
    TestERC20 public baseAsset;
    mapping(address => uint256) public balances;
    uint256 public valuePerShare;
    int256 public baseAssetSlippage;

    constructor(TestERC20 _underlyer, TestERC20 _baseAsset) {
        underlyer = _underlyer;
        baseAsset = _baseAsset;
    }

    function decimals() external pure returns (uint8) {
        return 18;
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
        baseAssetSlippage = slippage;
    }

    function withdrawBaseAsset(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = uint256(int256((shares * valuePerShare / 1e18)) - baseAssetSlippage);
        baseAsset.mint(receiver, assets);
        baseAssetSlippage = 0;
        balances[msg.sender] -= shares;
    }

    function balanceOf(address wallet) external view returns (uint256) {
        return balances[wallet];
    }
}

contract TestLMPVault is LMPVault {
    using WithdrawalQueue for StructuredLinkedList.List;
    using EnumerableSet for EnumerableSet.AddressSet;
    using AutoPoolToken for AutoPoolToken.TokenData;

    bool private _nextDepositGetsDoubleShares;

    constructor(ISystemRegistry _systemRegistry, address _vaultAsset) LMPVault(_systemRegistry, _vaultAsset) { }

    function nextDepositGetsDoubleShares() public {
        _nextDepositGetsDoubleShares = true;
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

    function isInWithdrawalQueue(address addr) external view returns (bool ret) {
        ret = _withdrawalQueue.addressExists(addr);
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
}

contract FeeAndProfitTestVault is TestLMPVault {
    uint256 private _feeSharesToBeCollected;

    constructor(ISystemRegistry _systemRegistry, address _vaultAsset) TestLMPVault(_systemRegistry, _vaultAsset) { }

    function feesAndProfitHandling(uint256 newIdle, uint256 newDebt, uint256 startingTotalAssets) public {
        _feeAndProfitHandling(newIdle + newDebt, startingTotalAssets);
    }

    function setUnlockPeriodInSeconds(uint48 unlockPeriod) public {
        _profitUnlockSettings.unlockPeriodInSeconds = unlockPeriod;
    }

    function setLastProfitUnlockTime(uint256 lastUnlockTime) public {
        _profitUnlockSettings.lastProfitUnlockTime = uint48(lastUnlockTime);
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

    function _collectFees(uint256, uint256 currentTotalSupply) internal virtual override returns (uint256) {
        uint256 shares = _feeSharesToBeCollected;
        _feeSharesToBeCollected = 0;

        mint(address(4335), shares);

        return currentTotalSupply + shares;
    }
}
