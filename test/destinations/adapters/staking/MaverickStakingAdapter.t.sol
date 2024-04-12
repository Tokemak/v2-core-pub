// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { MaverickStakingAdapter } from "src/destinations/adapters/staking/MaverickStakingAdapter.sol";

// solhint-disable func-name-mixedcase
contract MaverickStakingAdapterTest is Test {
    IReward private rewarder;
    IERC20 private stakingToken;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint);
        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        rewarder = IReward(0x14edfe68031bBf229a765919EB52AE6F6F3347d4);
        stakingToken = IERC20(rewarder.stakingToken());
    }

    function test_Revert_Staking_ZeroAddress_For_Reward() external {
        vm.expectRevert();
        MaverickStakingAdapter.stakeLPs(IReward(address(0)), 5);
    }

    function test_Revert_Staking_ZeroAmount() external {
        vm.expectRevert();
        MaverickStakingAdapter.stakeLPs(rewarder, 0);
    }

    function test_Revert_Unstaking_ZeroAddress_For_Reward() external {
        vm.expectRevert();
        MaverickStakingAdapter.unstakeLPs(IReward(address(0)), 5);
    }

    function test_Revert_Unstaking_ZeroAmount() external {
        vm.expectRevert();
        MaverickStakingAdapter.unstakeLPs(rewarder, 0);
    }

    function test_Full_Staking_Lifecycle() public {
        deal(address(stakingToken), address(this), 10 * 1e18);

        // Stake LPs
        uint256 preStakeRewarderBalance = rewarder.balanceOf(address(this));
        uint256 preStakeLpBalance = stakingToken.balanceOf(address(this));

        uint256 amount = 5;
        MaverickStakingAdapter.stakeLPs(rewarder, amount);

        uint256 afterStakeRewarderBalance = rewarder.balanceOf(address(this));
        uint256 afterStakeLpBalance = stakingToken.balanceOf(address(this));

        assertEq(afterStakeRewarderBalance, preStakeRewarderBalance + amount);
        assertEq(afterStakeLpBalance, preStakeLpBalance - amount);

        // Unstake LPs
        MaverickStakingAdapter.unstakeLPs(rewarder, amount);

        uint256 afterUnstakeRewarderBalance = rewarder.balanceOf(address(this));
        uint256 afterUnstakeLpBalance = stakingToken.balanceOf(address(this));

        assertEq(afterUnstakeRewarderBalance, preStakeRewarderBalance);
        assertEq(afterUnstakeLpBalance, preStakeLpBalance);
    }
}
