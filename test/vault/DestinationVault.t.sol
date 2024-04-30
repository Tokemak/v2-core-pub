// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase */

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Errors } from "src/utils/Errors.sol";
import { Test } from "forge-std/Test.sol";
import { IDestinationVault, DestinationVault } from "src/vault/DestinationVault.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Roles } from "src/libs/Roles.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";

contract DestinationVaultBaseTests is Test {
    using Clones for address;

    address private testUser1;
    address private testUser2;

    SystemRegistry private systemRegistry;
    IAccessController private accessController;
    IMainRewarder private mainRewarder;
    ILMPVaultRegistry private lmpVaultRegistry;

    TestERC20 private baseAsset;
    TestERC20 private underlyer;
    TestIncentiveCalculator private testIncentiveCalculator;

    address private testVaultTemplate;
    TestDestinationVault private testVault;

    address private pool;

    IRootPriceOracle private _rootPriceOracle;

    address private _weth;

    event Shutdown(IDestinationVault.VaultShutdownStatus reason);
    event UnderlyerRecovered(address destination, uint256 amount);

    function setUp() public {
        testUser1 = vm.addr(1);
        testUser2 = vm.addr(2);
        pool = vm.addr(234_234);
        mainRewarder = IMainRewarder(vm.addr(3));
        lmpVaultRegistry = ILMPVaultRegistry(vm.addr(3));

        _weth = address(new TestERC20("weth", "weth"));
        vm.label(_weth, "weth");

        systemRegistry = new SystemRegistry(vm.addr(100), _weth);
        mockSystemBound(address(lmpVaultRegistry), address(systemRegistry));

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        systemRegistry.setLMPVaultRegistry(address(lmpVaultRegistry));

        accessController.grantRole(Roles.DESTINATION_VAULT_MANAGER, address(this));

        baseAsset = new TestERC20("ABC", "ABC");
        underlyer = new TestERC20("DEF", "DEF");
        underlyer.setDecimals(6);

        testIncentiveCalculator = new TestIncentiveCalculator();
        testIncentiveCalculator.setLpToken(address(underlyer));
        testVaultTemplate = address(new TestDestinationVault(systemRegistry));

        testVault = TestDestinationVault(testVaultTemplate.cloneDeterministic(bytes32(0)));

        testVault.initialize(
            baseAsset, underlyer, mainRewarder, address(testIncentiveCalculator), new address[](0), abi.encode("")
        );

        testVault.setPool(pool);

        _rootPriceOracle = IRootPriceOracle(vm.addr(34_399));
        vm.label(address(_rootPriceOracle), "rootPriceOracle");

        mockSystemBound(address(_rootPriceOracle), address(systemRegistry));
        systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        // TestUser1 starts with 100 ABC
        baseAsset.mint(testUser1, 100);

        // Token deployer gets 1000 ABC
        baseAsset.mint(address(this), 1000);

        // TestUser1 starts with 100 DEF
        underlyer.mint(testUser1, 100);

        // Token deployer gets 1000 DEF
        underlyer.mint(address(this), 1000);

        _mockRootPrice(_weth, 1 ether);
    }

    function test_debtValue_PriceInTermsOfBaseAssetWhenWeth() public {
        TestDestinationVault bav = TestDestinationVault(testVaultTemplate.cloneDeterministic(bytes32("2")));
        bav.setPool(pool);

        bav.initialize(
            IERC20(_weth), underlyer, mainRewarder, address(testIncentiveCalculator), new address[](0), abi.encode("")
        );

        _mockRootPriceGetRangesPriceLP(address(underlyer), pool, _weth, 1 ether, 2 ether, true);
        assertEq(bav.debtValue(10e6), 20 ether);
    }

    function testIncentiveCalculatorHasSameUnderlying() public {
        testIncentiveCalculator = new TestIncentiveCalculator();
        testIncentiveCalculator.setLpToken(address(0));

        TestDestinationVault wethVault = TestDestinationVault(testVaultTemplate.cloneDeterministic(bytes32("1")));

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, address(0), address(underlyer), "lp"
            )
        );
        wethVault.initialize(
            IERC20(_weth), underlyer, mainRewarder, address(testIncentiveCalculator), new address[](0), abi.encode("")
        );
    }

    function testIncentiveCalculatorReturnsStats() public {
        assertEq(address(testVault.getStats()), address(testIncentiveCalculator));
    }

    function testVaultNameIsWithConstituentValues() public {
        string memory name = testVault.name();

        assertEq(name, "Tokemak-ABC-DEF");
    }

    function testVaultSymbolIsWithConstituentValues() public {
        string memory symbol = testVault.symbol();

        assertEq(symbol, "toke-ABC-DEF");
    }

    function testVaultUsesUnderlyerDecimals() public {
        uint8 decimals = testVault.decimals();
        assertEq(decimals, underlyer.decimals());
    }

    function testOnlyLmpVaultCanDepositUnderlying() public {
        mockIsLmpVault(address(this), false);
        underlyer.approve(address(testVault), 10);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        testVault.depositUnderlying(10);

        mockIsLmpVault(address(this), true);

        testVault.depositUnderlying(10);
    }

    function testShutdownOnlyAccessibleByOwner() public {
        mockIsLmpVault(address(this), false);
        underlyer.approve(address(testVault), 10);

        address caller = address(5);

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        testVault.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        vm.stopPrank();
    }

    function testIsShutdownProperlyReportsWithEvent() public {
        // verify "not shutdown" / "active" first
        assertEq(testVault.isShutdown(), false);
        if (testVault.shutdownStatus() != IDestinationVault.VaultShutdownStatus.Active) {
            assert(false);
        }

        // test invalid reason
        vm.expectRevert(
            abi.encodeWithSelector(
                IDestinationVault.InvalidShutdownStatus.selector, IDestinationVault.VaultShutdownStatus.Active
            )
        );
        testVault.shutdown(IDestinationVault.VaultShutdownStatus.Active);

        // test proper shutdown
        vm.expectEmit(true, true, true, true);
        emit Shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        testVault.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);

        // verify shutdown
        assertEq(testVault.isShutdown(), true);
        if (testVault.shutdownStatus() != IDestinationVault.VaultShutdownStatus.Deprecated) {
            assert(false);
        }
    }

    function testCannotDepositWhenShutdown() public {
        mockIsLmpVault(address(this), false);
        underlyer.approve(address(testVault), 10);
        mockIsLmpVault(address(this), true);

        testVault.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);

        vm.expectRevert(abi.encodeWithSelector(DestinationVault.VaultShutdown.selector));
        testVault.depositUnderlying(10);
    }

    function testUnderlyingDepositMintsEqualShares() public {
        uint256 depositAmount = 10;
        uint256 originalBalance = testVault.balanceOf(address(this));

        mockIsLmpVault(address(this), true);
        underlyer.approve(address(testVault), depositAmount);
        uint256 shares = testVault.depositUnderlying(depositAmount);

        uint256 afterBalance = testVault.balanceOf(address(this));

        assertEq(afterBalance - originalBalance, depositAmount);
        assertEq(shares, depositAmount);
    }

    function testUnderlyingDepositPullsCorrectUnderlyingAmt() public {
        uint256 depositAmount = 10;
        uint256 originalBalance = underlyer.balanceOf(address(this));

        mockIsLmpVault(address(this), true);
        underlyer.approve(address(testVault), depositAmount);
        testVault.depositUnderlying(depositAmount);

        uint256 afterBalance = underlyer.balanceOf(address(this));

        assertEq(originalBalance - afterBalance, depositAmount);
    }

    function testOnlyLmpVaultCanWithdrawUnderlying() public {
        // Deposit
        uint256 depositAmount = 10;
        mockIsLmpVault(address(this), true);
        underlyer.approve(address(testVault), depositAmount);
        testVault.depositUnderlying(depositAmount);

        // No Longer LMP
        mockIsLmpVault(address(this), false);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        testVault.withdrawUnderlying(10, address(this));

        // LMP again
        mockIsLmpVault(address(this), true);
        testVault.withdrawUnderlying(10, address(this));
    }

    function testCanWithdrawUnderlyingWhenShutdown() public {
        // Deposit
        uint256 depositAmount = 10;
        mockIsLmpVault(address(this), true);
        underlyer.approve(address(testVault), depositAmount);
        testVault.depositUnderlying(depositAmount);
        testVault.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);

        // LMP again
        mockIsLmpVault(address(this), true);
        testVault.withdrawUnderlying(10, address(this));
    }

    function testUnderlyingWithdrawBurnsEqualShare() public {
        address localTestUser = vm.addr(1000);
        uint256 beforeBalance = underlyer.balanceOf(localTestUser);

        // Deposit
        uint256 depositAmount = 10;
        mockIsLmpVault(address(this), true);
        underlyer.approve(address(testVault), depositAmount);
        testVault.depositUnderlying(depositAmount);
        uint256 beforeVaultShareBalance = testVault.balanceOf(address(this));
        uint256 amtRet = testVault.withdrawUnderlying(10, localTestUser);

        uint256 afterBalance = underlyer.balanceOf(localTestUser);
        uint256 afterVaultShareBalance = testVault.balanceOf(address(this));

        assertEq(afterBalance - beforeBalance, depositAmount);
        assertEq(beforeVaultShareBalance - afterVaultShareBalance, depositAmount);
        assertEq(amtRet, depositAmount);
    }

    function test_recoverUnderlying_RevertsWrongRole() external {
        vm.expectRevert(Errors.AccessDenied.selector);
        testVault.recoverUnderlying(address(2));
    }

    function test_recoverUnderlying_RevertsZeroAddress() external {
        accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, vm.addr(4));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "destination"));
        vm.prank(vm.addr(4));
        testVault.recoverUnderlying(address(0));
    }

    function test_recoverUnderlying_RevertsNothingToRecover() external {
        accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, vm.addr(4));
        vm.expectRevert(DestinationVault.NothingToRecover.selector);
        vm.prank(vm.addr(4));
        testVault.recoverUnderlying(vm.addr(55));
    }

    function test_recoverUnderlying_RunsProperly_RecoverInternal() external {
        // Set up access
        accessController.setupRole(Roles.TOKEN_RECOVERY_MANAGER, vm.addr(4));

        // Get tokens, transfer directly to vault to avoid being picked up in debt tracking.
        deal(address(underlyer), address(this), 1000);
        underlyer.transfer(address(testVault), 1000);

        // Check tokens in vault and destination address.
        assertEq(underlyer.balanceOf(address(testVault)), 1000);
        assertEq(underlyer.balanceOf(vm.addr(55)), 0);

        // Check event.
        vm.expectEmit(false, false, false, true);
        emit UnderlyerRecovered(vm.addr(55), 1000);
        vm.prank(vm.addr(4));
        testVault.recoverUnderlying(vm.addr(55));

        // Balance checks
        assertEq(underlyer.balanceOf(address(testVault)), 0);
        assertEq(underlyer.balanceOf(vm.addr(55)), 1000);
    }

    function test_getValidatedSpotPrice_RevertsWhenNotSafe() public {
        _mockRootPriceGetRangesPriceLP(1, 2, false);

        vm.expectRevert(abi.encodeWithSelector(DestinationVault.PricesOutOfRange.selector, 1, 2));
        testVault.getValidatedSpotPrice();
    }

    function test_getValidatedSpotPrice_ReturnsSpotPriceFromOracle() public {
        _mockRootPriceGetRangesPriceLP(3, 2, true);

        uint256 spotPrice = testVault.getValidatedSpotPrice();
        assertEq(spotPrice, 3);
    }

    function test_getPool_ReturnsPool() public {
        assertEq(testVault.getPool(), pool);
    }

    function test_getRangePricesLP_ProxiesCallToRootOracle() public {
        _mockRootPriceGetRangesPriceLP(3, 4, true);

        vm.expectCall(
            address(_rootPriceOracle),
            abi.encodeCall(_rootPriceOracle.getRangePricesLP, (address(underlyer), pool, address(baseAsset)))
        );
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) = testVault.getRangePricesLP();

        assertEq(spotPrice, 3, "spotPrice");
        assertEq(safePrice, 4, "safePrice");
        assertEq(isSpotSafe, true, "isSpotSafe");
    }

    function test_getUnderlyerFloorPrice_ProxiesCallToRootOracle() public {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(
                IRootPriceOracle.getFloorPrice.selector, address(underlyer), pool, address(baseAsset)
            ),
            abi.encode(3)
        );

        vm.expectCall(
            address(_rootPriceOracle),
            abi.encodeCall(_rootPriceOracle.getFloorPrice, (address(underlyer), pool, address(baseAsset)))
        );
        uint256 floorPrice = testVault.getUnderlyerFloorPrice();

        assertEq(floorPrice, 3, "floorPrice");
    }

    function test_getUnderlyerCeilingPrice_ProxiesCallToRootOracle() public {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(
                IRootPriceOracle.getCeilingPrice.selector, address(underlyer), pool, address(baseAsset)
            ),
            abi.encode(7)
        );

        vm.expectCall(
            address(_rootPriceOracle),
            abi.encodeCall(_rootPriceOracle.getCeilingPrice, (address(underlyer), pool, address(baseAsset)))
        );
        uint256 ceilingPrice = testVault.getUnderlyerCeilingPrice();

        assertEq(ceilingPrice, 7, "ceilingPrice");
    }

    function mockSystemBound(address addr, address systemRegistry_) internal {
        vm.mockCall(
            addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(systemRegistry_)
        );
    }

    function mockIsLmpVault(address addr, bool isVault) internal {
        vm.mockCall(
            address(lmpVaultRegistry),
            abi.encodeWithSelector(ILMPVaultRegistry.isVault.selector, addr),
            abi.encode(isVault)
        );
    }

    function _mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function _mockRootPriceGetRangesPriceLP(uint256 spotPrice, uint256 safePrice, bool isSafe) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(
                IRootPriceOracle.getRangePricesLP.selector, address(underlyer), pool, address(baseAsset)
            ),
            abi.encode(spotPrice, safePrice, isSafe)
        );
    }

    function _mockRootPriceGetRangesPriceLP(
        address underlyer_,
        address pool_,
        address baseAsset_,
        uint256 spotPrice,
        uint256 safePrice,
        bool isSafe
    ) internal {
        vm.mockCall(
            address(_rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector, underlyer_, pool_, baseAsset_),
            abi.encode(spotPrice, safePrice, isSafe)
        );
    }
}
