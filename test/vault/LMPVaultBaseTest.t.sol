// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IDestinationVault } from "src/vault/DestinationVault.sol";
import { IAutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { Errors, SystemRegistry } from "src/SystemRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { TestDestinationVault } from "test/mocks/TestDestinationVault.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";

contract AutopoolETHBaseTest is BaseTest {
    using SafeERC20 for IERC20;
    using Clones for address;

    IDestinationVault public destinationVault;
    IDestinationVault public destinationVault2;
    AutopoolETH public autoPool;
    TestDestinationVault public vaultTemplate;

    address private autoPoolStrategy = vm.addr(100_001);
    address private unauthorizedUser = address(0x33);

    error DestinationLimitExceeded();

    event DestinationVaultAdded(address destination);
    event DestinationVaultRemoved(address destination);
    event WithdrawalQueueSet(address[] destinations);
    event RewarderSet(address newRewarder, address oldRewarder);

    function setUp() public virtual override(BaseTest) {
        BaseTest.setUp();

        deployAutopoolRegistry();
        deployAutopoolFactory();

        //
        // create and initialize factory
        //

        // create destination vault mocks
        vaultTemplate = new TestDestinationVault(systemRegistry);

        destinationVault = _createDestinationVault(address(baseAsset), keccak256("salt1"));
        destinationVault2 = _createDestinationVault(address(baseAsset), keccak256("salt2"));

        accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_REWARD_MANAGER, address(this));

        // create test autoPool
        IAutopoolFactory vaultFactory = systemRegistry.getAutopoolFactoryByType(VaultTypes.LST);
        vaultFactory.addStrategyTemplate(autoPoolStrategy);
        accessController.grantRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, address(vaultFactory));

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(SystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        vm.mockCall(
            autoPoolStrategy,
            abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector),
            abi.encode(systemRegistry)
        );

        bytes memory initData = abi.encode("");
        bytes32 template = keccak256("vault");
        autoPool =
            AutopoolETH(vaultFactory.createVault{ value: 100_000 }(autoPoolStrategy, "x", "y", template, initData));

        assert(systemRegistry.autoPoolRegistry().isVault(address(autoPool)));
    }

    function _createDestinationVault(address asset, bytes32 salt) internal returns (IDestinationVault) {
        address underlyer = address(new TestERC20("underlyer", "underlyer"));
        TestIncentiveCalculator testIncentiveCalculator = new TestIncentiveCalculator();
        testIncentiveCalculator.setLpToken(underlyer);

        IDestinationVault vault = IDestinationVault(address(vaultTemplate).cloneDeterministic(salt));
        vault.initialize(
            IERC20(asset),
            IERC20(underlyer),
            IMainRewarder(makeAddr("rewarder")),
            address(testIncentiveCalculator),
            new address[](0),
            abi.encode("")
        );

        // mock "isRegistered" call
        vm.mockCall(
            address(systemRegistry.destinationVaultRegistry()),
            abi.encodeWithSelector(destinationVaultRegistry.isRegistered.selector, address(vault)),
            abi.encode(true)
        );

        return vault;
    }

    //////////////////////////////////////////////////////////////////////
    //                                                                  //
    //				    Destination Vaults lists						                  //
    //                                                                  //
    //////////////////////////////////////////////////////////////////////

    function test_DestinationVault_add() public {
        _addDestinationVault(destinationVault);
        assert(autoPool.getDestinations()[0] == address(destinationVault));
    }

    function test_DestinationVault_add_permissions() public {
        vm.prank(unauthorizedUser);
        address[] memory destinations = new address[](1);
        destinations[0] = address(destinationVault);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        autoPool.addDestinations(destinations);
    }

    function test_DestinationVault_addExtra() public {
        _addDestinationVault(destinationVault);
        assert(autoPool.getDestinations()[0] == address(destinationVault));
        _addDestinationVault(destinationVault2);
        assert(autoPool.getDestinations().length == 2);
        assert(autoPool.getDestinations()[1] == address(destinationVault2));
    }

    function test_DestinationVault_remove() public {
        _addDestinationVault(destinationVault);
        assert(autoPool.getDestinations()[0] == address(destinationVault));
        _removeDestinationVault(destinationVault);
        assert(autoPool.getDestinations().length == 0);
    }

    function test_DestinationVault_remove_permissions() public {
        // test authorizations
        vm.prank(unauthorizedUser);
        address[] memory destinations = new address[](1);
        destinations[0] = address(destinationVault);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        autoPool.removeDestinations(destinations);
    }

    function _addDestinationVault(IDestinationVault _destination) internal {
        uint256 numDestinationsBefore = autoPool.getDestinations().length;
        address[] memory destinations = new address[](1);
        destinations[0] = address(_destination);
        vm.expectEmit(true, false, false, false);
        emit DestinationVaultAdded(destinations[0]);
        autoPool.addDestinations(destinations);
        assert(autoPool.getDestinations().length == numDestinationsBefore + 1);
    }

    function _removeDestinationVault(IDestinationVault _destination) internal {
        uint256 numDestinationsBefore = autoPool.getDestinations().length;
        address[] memory destinations = new address[](1);
        destinations[0] = address(_destination);
        vm.expectEmit(true, false, false, false);
        emit DestinationVaultRemoved(destinations[0]);
        autoPool.removeDestinations(destinations);
        assert(autoPool.getDestinations().length == numDestinationsBefore - 1);
    }

    //////////////////////////////////////////////////////////////////////
    //                                                                  //
    //			                Setting rewarder                      		  //
    //                                                                  //
    //////////////////////////////////////////////////////////////////////

    function test_RevertIncorrectRole_AndNotFactory() public {
        address notRoleOrFactory = makeAddr("NOT_REWARD_ROLE_OR_FACTORY");
        vm.startPrank(notRoleOrFactory);

        assertTrue(notRoleOrFactory != address(autoPoolFactory));
        assertTrue(!accessController.hasRole(Roles.AUTO_POOL_REWARD_MANAGER, notRoleOrFactory));

        vm.expectRevert(Errors.AccessDenied.selector);
        autoPool.setRewarder(makeAddr("REWARDER"));

        vm.stopPrank();
    }

    function test_RevertZeroAddress_setRewarder() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rewarder"));
        autoPool.setRewarder(address(0));
    }

    function test_FactoryCanSetRewarder() public {
        address rewarder = makeAddr("REWARDER");
        address oldRewarder = address(autoPool.rewarder());

        vm.prank(address(autoPoolFactory));
        vm.expectEmit(false, false, false, true);
        emit RewarderSet(rewarder, oldRewarder);

        autoPool.setRewarder(rewarder);

        assertEq(address(autoPool.rewarder()), rewarder);
    }

    function test_AutopoolRewardManagerRole_CanSetRewarder() public {
        assertTrue(accessController.hasRole(Roles.AUTO_POOL_REWARD_MANAGER, address(this)));

        address rewarder = makeAddr("REWARDER");
        address oldRewarder = address(autoPool.rewarder());

        vm.expectEmit(false, false, false, true);
        emit RewarderSet(rewarder, oldRewarder);
        autoPool.setRewarder(rewarder);

        assertEq(address(autoPool.rewarder()), rewarder);
    }

    function test_RewarderReplacedProperly() public {
        address firstRewarder = makeAddr("FIRST_REWARDER");
        address secondRewarder = makeAddr("SECOND_REWARDER");

        // Set first rewarder.
        autoPool.setRewarder(firstRewarder);
        assertEq(address(autoPool.rewarder()), firstRewarder);

        // Replace with new rewarder.
        vm.expectEmit(false, false, false, true);
        emit RewarderSet(secondRewarder, firstRewarder);

        autoPool.setRewarder(secondRewarder);

        assertEq(address(autoPool.rewarder()), secondRewarder);
        assertTrue(autoPool.isPastRewarder(firstRewarder));
    }

    function test_PastRewardersState_NotUpdatedFor_ReplacingZeroAddress() public {
        address rewarder = makeAddr("REWARDER");
        autoPool.setRewarder(rewarder);

        assertTrue(!autoPool.isPastRewarder(address(0)));
    }

    function test_RevertsWhenRewarderIsDuplicate() public {
        address factoryRewarder = address(autoPool.rewarder());

        vm.expectRevert(Errors.ItemExists.selector);
        autoPool.setRewarder(factoryRewarder);
    }

    function test_RevertsWhenPastRewarderIsDuplicate() public {
        address factoryRewarder = address(autoPool.rewarder());
        address nonFactoryRewarder = makeAddr("NOT_FACTORY_REWARDER");

        autoPool.setRewarder(nonFactoryRewarder);

        // Will revert for factory rewarder being in past rewarders EnumberableSet.
        vm.expectRevert(Errors.ItemExists.selector);

        autoPool.setRewarder(factoryRewarder);
    }

    //////////////////////////////////////////////////////////////////////
    //                                                                  //
    //			                Rewarder view functions                     //
    //                                                                  //
    //////////////////////////////////////////////////////////////////////

    function test_GetsAllPastRewarders() public {
        address rewarderOne = address(autoPool.rewarder()); // First rewarder set by factory creation.
        address rewarderTwo = makeAddr("REWARDER_TWO");
        address rewarderThree = makeAddr("REWARDER_THREE");

        // Set new rewarder twice, first two should be set to past rewarders.
        autoPool.setRewarder(rewarderTwo);
        autoPool.setRewarder(rewarderThree);

        address[] memory pastRewarders = autoPool.getPastRewarders();

        assertEq(pastRewarders.length, 2);
        // OZ says that there is no guarentee on ordering
        assertTrue(pastRewarders[0] == rewarderOne || pastRewarders[0] == rewarderTwo);
        assertTrue(pastRewarders[1] == rewarderOne || pastRewarders[1] == rewarderTwo);
    }

    function test_CorrectlyReturnsPastRewarder() public {
        address factoryRewarder = address(autoPool.rewarder());
        address nonFactoryRewarder = makeAddr("NOT_FACTORY_REWARDER");

        // Push factory rewarder to past rewarders.
        autoPool.setRewarder(nonFactoryRewarder);

        assertTrue(autoPool.isPastRewarder(factoryRewarder));
    }

    //////////////////////////////////////////////////////////////////////
    //                                                                  //
    //			                Rebalancer                      		        //
    //                                                                  //
    //////////////////////////////////////////////////////////////////////

    // function test_FlashRebalancer() public {
    //     (address autoPoolAddress, address dAddress1, address dAddress2, address baseAssetAddress) =
    //         _setupRebalancerInitialState();

    //     // do actual rebalance, target shares: d1=75, d2=25
    //     deal(address(baseAsset), address(this), 25);
    //     autoPool.flashRebalance(
    //         IERC3156FlashBorrower(address(this)), dAddress2, baseAssetAddress, 25, dAddress1, baseAssetAddress, 25,
    // ""
    //     );

    //     // check final balances
    //     assertEq(destinationVault.balanceOf(autoPoolAddress), 75, "final autoPool d1's shares != 75");
    //     assertEq(destinationVault2.balanceOf(autoPoolAddress), 25, "final autoPool d2's shares != 25");
    // }

    function test_FlashRebalancer_permissions() public {
        vm.prank(unauthorizedUser);
        address x = address(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        IStrategy.RebalanceParams memory params = IStrategy.RebalanceParams({
            destinationIn: x,
            tokenIn: x,
            amountIn: 1,
            destinationOut: x,
            tokenOut: x,
            amountOut: 1
        });
        autoPool.flashRebalance(IERC3156FlashBorrower(address(this)), params, "");
    }

    // @dev Callback support from autoPool to provide underlying for the "IN"
    function onFlashLoan(
        address, /* initiator */
        address token,
        uint256 amount,
        uint256,
        bytes calldata
    ) external returns (bytes32) {
        // transfer dv underlying lp from swapper to here
        IERC20(token).safeTransfer(msg.sender, amount);

        // @dev required as per spec to signify success
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _setupRebalancerInitialState()
        public
        returns (address autoPoolAddress, address dAddress1, address dAddress2, address baseAssetAddress)
    {
        // add destination vaults
        _addDestinationVault(destinationVault);
        _addDestinationVault(destinationVault2);

        autoPoolAddress = address(autoPool);
        dAddress1 = address(destinationVault);
        dAddress2 = address(destinationVault2);
        baseAssetAddress = address(baseAsset);

        // initial desired state of autoPool balance in destination vaults:
        //
        // DestinationVault1: 100 shares
        // DestinationVault2: 0 shares

        // init swapper balance
        deal(address(baseAsset), address(this), 100);
        // approve autoPool's spending of underlyer
        baseAsset.approve(autoPoolAddress, 25);

        // init d1's autoPool shares
        deal(address(baseAsset), dAddress1, 100); // enough underlying for math to work
        deal(dAddress1, autoPoolAddress, 100); // d1's shares to autoPool
        assertEq(destinationVault.balanceOf(autoPoolAddress), 100, "initial: autoPool shares in d1 != 100");
        assertEq(destinationVault2.balanceOf(autoPoolAddress), 0, "initial: autoPool shares in d2 != 0");
    }
}
