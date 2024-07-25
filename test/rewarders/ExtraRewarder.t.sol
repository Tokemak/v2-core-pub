/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ExtraRewarder } from "src/rewarders/ExtraRewarder.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { RANDOM, WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";

contract ExtraRewarderTest is Test {
    ExtraRewarder public rewarder;
    ERC20Mock public rewardToken;

    address public mainRewarder;
    SystemRegistry public systemRegistry;
    AccessController public accessController;

    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 100;
    uint256 public totalSupply = 100;

    event Withdrawn(address indexed user, uint256 amount);

    event UserRewardUpdated(
        address indexed user, uint256 amount, uint256 rewardPerTokenStored, uint256 lastUpdateBlock
    );

    function setUp() public virtual {
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);
        mainRewarder = makeAddr("MAIN_REWARDER");

        // mock stake tracker totalSupply function by default
        vm.mockCall(mainRewarder, abi.encodeWithSelector(IBaseRewarder.totalSupply.selector), abi.encode(totalSupply));

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        rewarder = new ExtraRewarder(
            systemRegistry, address(rewardToken), address(mainRewarder), newRewardRatio, durationInBlock
        );
    }
}

contract ConstructorTest is ExtraRewarderTest {
    function test_RevertIf_MainReward_AddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_mainReward"));

        new ExtraRewarder(systemRegistry, address(rewardToken), address(0), newRewardRatio, durationInBlock);
    }

    function test_SetsMainRewarder() public {
        rewarder = new ExtraRewarder(
            systemRegistry, address(rewardToken), address(mainRewarder), newRewardRatio, durationInBlock
        );

        assertEq(address(rewarder.mainReward()), address(mainRewarder));
    }
}

contract WithdrawTest is ExtraRewarderTest {
    uint256 public constant STAKE_WITHDRAW_AMOUNT = 1e18;

    address public stakeWithdrawFor = makeAddr("STAKE_WITHDRAW_FOR");

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(address(mainRewarder));
        rewarder.stake(stakeWithdrawFor, STAKE_WITHDRAW_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertIf_NotMainRewarder() public {
        vm.expectRevert(ExtraRewarder.MainRewardOnly.selector);
        rewarder.withdraw(stakeWithdrawFor, STAKE_WITHDRAW_AMOUNT);
    }

    function test_WithdrawWorks() public {
        vm.prank(address(mainRewarder));

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(stakeWithdrawFor, STAKE_WITHDRAW_AMOUNT);

        rewarder.withdraw(stakeWithdrawFor, STAKE_WITHDRAW_AMOUNT);
    }
}

contract GetReward is ExtraRewarderTest {
    function test_RevertIf_ClaimForOther() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.getReward(RANDOM, RANDOM);
    }

    function test_CanClaimForYourself() public {
        vm.mockCall(address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(10));

        vm.prank(RANDOM);
        rewarder.getReward(RANDOM, RANDOM);
    }

    function test_OnlyMainRewarderCanClaimForOther() public {
        vm.mockCall(address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(10));

        vm.prank(mainRewarder);
        rewarder.getReward(RANDOM, RANDOM);
    }

    function test_UserCanClaimRewardDirectly() public {
        vm.mockCall(address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(10));

        vm.expectEmit(true, true, true, false);
        emit UserRewardUpdated(address(this), 0, 0, 0);

        rewarder.getReward();
    }
}

// Testing inherited AbstractRewarder RBAC functionalities with rewarder specific to extra rewards.
contract RoleBasedAccessControlTests is ExtraRewarderTest {
    function test_RBAC_setTokeLockDuration() external {
        // Mock registry / accToke calls.
        address fakeAccToke = makeAddr("FAKE_ACCTOKE");
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.accToke.selector), abi.encode(fakeAccToke)
        );
        vm.mockCall(fakeAccToke, abi.encodeWithSignature("minStakeDuration()"), abi.encode(0));

        // `address(this)` does not have `EXTRA_REWARD_MANAGER`.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.setTokeLockDuration(5);

        // Grant `EXTRA_REWARD_MANAGER` to `address(this)`.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER, address(this));
        rewarder.setTokeLockDuration(5);
        assertEq(rewarder.tokeLockDuration(), 5);
    }

    function test_RBAC_addToWhitelist() external {
        address fakeWhitelisted = makeAddr("FAKE_WHITELIST");

        // `address(this)` does not have correct role.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.addToWhitelist(fakeWhitelisted);

        // Grant role, try again.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER, address(this));
        rewarder.addToWhitelist(fakeWhitelisted);
        assertEq(rewarder.whitelistedAddresses(fakeWhitelisted), true);
    }

    function test_RBAC_removeFromWhitelist() external {
        address fakeWhitelisted = makeAddr("FAKE_WHITELIST");
        address extraRewardRoleAddress = vm.addr(1);

        // Set up role for `vm.addr(1)`, add address to whitelist.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER, extraRewardRoleAddress);
        vm.startPrank(extraRewardRoleAddress);
        rewarder.addToWhitelist(fakeWhitelisted);
        vm.stopPrank();

        // `address(this)` does not have correct role.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.removeFromWhitelist(fakeWhitelisted);

        // Grant role, try again.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER, address(this));
        rewarder.removeFromWhitelist(fakeWhitelisted);
        assertEq(rewarder.whitelistedAddresses(fakeWhitelisted), false);
    }
}
