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
import { MainRewarder } from "src/rewarders/MainRewarder.sol";
import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";
import { Errors } from "src/utils/Errors.sol";
import { RANDOM, WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";

contract MainRewarderTest is Test {
    MainRewarder public rewarder;
    ERC20Mock public rewardToken;

    address public stakeTracker;
    SystemRegistry public systemRegistry;

    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 100;
    uint256 public totalSupply = 100;

    function setUp() public {
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);
        stakeTracker = makeAddr("STAKE_TRACKER");

        // mock stake tracker totalSupply function by default
        vm.mockCall(
            address(stakeTracker), abi.encodeWithSelector(IBaseRewarder.totalSupply.selector), abi.encode(totalSupply)
        );

        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );

        rewarder = new MainRewarder(
            systemRegistry,
            address(stakeTracker),
            address(rewardToken),
            newRewardRatio,
            durationInBlock,
            true
        );
    }
}

contract Stake is MainRewarderTest {
    function test_RevertIf_CallerIsNotStakeTracker() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.stake(RANDOM, 1000);
    }

    function test_IncreasesUsersBalancesAndTotalSupply() public {
        uint256 deposit = 1000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        vm.startPrank(stakeTracker);
        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);
        rewarder.stake(user3, deposit);
        vm.stopPrank();

        assertEq(rewarder.balanceOf(user1), deposit);
        assertEq(rewarder.balanceOf(user2), deposit);
        assertEq(rewarder.balanceOf(user3), deposit);

        assertEq(rewarder.totalSupply(), deposit * 3);
    }
}

contract Withdraw is MainRewarderTest {
    function test_RevertIf_CallerIsNotStakeTracker() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewarder.withdraw(RANDOM, 1000, false);
    }

    function test_DecreasesUsersBalancesAndTotalSupply() public {
        uint256 deposit = 1000;

        address user1 = makeAddr("USER1");
        address user2 = makeAddr("USER2");
        address user3 = makeAddr("USER3");

        vm.startPrank(stakeTracker);

        // stake for 3 users
        rewarder.stake(user1, deposit);
        rewarder.stake(user2, deposit);
        rewarder.stake(user3, deposit);

        // withdraw for user3
        rewarder.withdraw(user3, deposit, false);

        assertEq(rewarder.balanceOf(user3), 0);
        assertEq(rewarder.totalSupply(), deposit * 2);

        vm.stopPrank();
    }
}
