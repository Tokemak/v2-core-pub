/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ExtraRewarder } from "src/rewarders/ExtraRewarder.sol";
import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";
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

    function setUp() public {
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

contract GetReward is ExtraRewarderTest {
    function test_RevertIf_ClaimForOther() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.getReward(RANDOM);
    }

    function test_CanClaimForYourself() public {
        vm.mockCall(address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(10));

        vm.prank(RANDOM);
        rewarder.getReward(RANDOM);
    }

    function test_OnlyMainRewarderCanClaimForOther() public {
        vm.mockCall(address(mainRewarder), abi.encodeWithSelector(IBaseRewarder.balanceOf.selector), abi.encode(10));

        vm.prank(mainRewarder);
        rewarder.getReward(RANDOM);
    }
}

// Testing inherited AbstractRewarder RBAC functionalities with rewarder specific to extra rewards.
contract RoleBasedAccessControlTests is ExtraRewarderTest {
    function test_RBAC_setTokeLockDuration() external {
        // Mock registry / accToke calls.
        address fakeAccToke = makeAddr("FAKE_ACCTOKE");
        vm.mockCall(address(systemRegistry), abi.encodeWithSignature("accToke()"), abi.encode(fakeAccToke));
        vm.mockCall(fakeAccToke, abi.encodeWithSignature("minStakeDuration()"), abi.encode(0));

        // `address(this)` does not have `EXTRA_REWARD_MANAGER_ROLE`.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.setTokeLockDuration(5);

        // Grant `EXTRA_REWARD_MANAGER_ROLE` to `address(this)`.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER_ROLE, address(this));
        rewarder.setTokeLockDuration(5);
        assertEq(rewarder.tokeLockDuration(), 5);
    }

    function test_RBAC_addToWhitelist() external {
        address fakeWhitelisted = makeAddr("FAKE_WHITELIST");

        // `address(this)` does not have correct role.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.addToWhitelist(fakeWhitelisted);

        // Grant role, try again.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER_ROLE, address(this));
        rewarder.addToWhitelist(fakeWhitelisted);
        assertEq(rewarder.whitelistedAddresses(fakeWhitelisted), true);
    }

    function test_RBAC_removeFromWhitelist() external {
        address fakeWhitelisted = makeAddr("FAKE_WHITELIST");
        address extraRewardRoleAddress = vm.addr(1);

        // Set up role for `vm.addr(1)`, add address to whitelist.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER_ROLE, extraRewardRoleAddress);
        vm.startPrank(extraRewardRoleAddress);
        rewarder.addToWhitelist(fakeWhitelisted);
        vm.stopPrank();

        // `address(this)` does not have correct role.
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.removeFromWhitelist(fakeWhitelisted);

        // Grant role, try again.
        accessController.setupRole(Roles.EXTRA_REWARD_MANAGER_ROLE, address(this));
        rewarder.removeFromWhitelist(fakeWhitelisted);
        assertEq(rewarder.whitelistedAddresses(fakeWhitelisted), false);
    }
}
