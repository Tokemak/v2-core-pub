// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,gas-custom-errors */

import { Test } from "forge-std/Test.sol";
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { WETH_MAINNET, TOKE_MAINNET } from "test/utils/Addresses.sol";
import { AutoPoolMainRewarder } from "src/rewarders/AutoPoolMainRewarder.sol";

contract AutoPoolMainRewarderTest is Test {
    AutoPoolMainRewarder public rewarder;
    ERC20Mock public rewardToken;
    ERC20Mock public stakingToken;
    SystemRegistry public systemRegistry;
    AccessController public accessController;
    uint256 public newRewardRatio = 800;
    uint256 public durationInBlock = 100_000;
    uint256 public totalSupply = 100;
    uint256 public constant MAX_STAKE_AMOUNT = 100e6 * 1e18; // 100m

    event ExtraRewardAdded(address reward);
    event ExtraRewardsCleared();
    event ExtraRewardRemoved(address reward);

    function setUp() public virtual {
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        rewardToken = new ERC20Mock("MAIN_REWARD", "MAIN_REWARD", address(this), 0);
        stakingToken = new ERC20Mock("stakingToken", "stakingToken", address(this), 0);
        rewarder = new AutoPoolMainRewarder(
            systemRegistry, address(rewardToken), newRewardRatio, durationInBlock, true, address(stakingToken)
        );
        accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));
        accessController.grantRole(Roles.AUTO_POOL_REWARD_MANAGER, address(this));
    }

    /// @notice Tests that users can't withdraw more than their staked amount.
    function testFuzz_EnsureYouCannotWithdrawMoreThanYouPutIn(uint256[] memory withdrawAmounts) public {
        uint256 length = withdrawAmounts.length;
        vm.assume(length < 100); // Limit array size for efficiency.

        address[] memory users = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            // Ensure valid withdrawal amounts and create unique user addresses.
            vm.assume(withdrawAmounts[i] > 0 && withdrawAmounts[i] < (MAX_STAKE_AMOUNT / length));
            users[i] = makeAddr(Strings.toString(i));
        }

        // Stake amounts for each user.
        for (uint256 i = 0; i < length; i++) {
            stakingToken.mint(users[i], withdrawAmounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(rewarder), withdrawAmounts[i]);
            rewarder.stake(users[i], withdrawAmounts[i]);
            vm.stopPrank();
        }

        // Advance time for randomness in staking.
        vm.roll(block.number + 7200 * 10); // 10 days in blocks.
        vm.warp(block.timestamp + 10 days); // 10 days in timestamp.

        // Check if staked amounts match expected balances.
        for (uint256 i = 0; i < length; i++) {
            assertEq(rewarder.balanceOf(users[i]), withdrawAmounts[i]);
        }

        // Test withdrawal behavior: should revert on over-withdrawal, succeed on exact amount.
        for (uint256 i = 0; i < length; i++) {
            vm.startPrank(users[i]);
            // Expect revert on withdrawing more than staked (overflow/underflow).
            vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), 0x11));
            rewarder.withdraw(users[i], withdrawAmounts[i] + 1, false);

            // Withdraw exact staked amount and check for zero balance.
            rewarder.withdraw(users[i], withdrawAmounts[i], false);
            assertEq(rewarder.balanceOf(users[i]), 0);
            vm.stopPrank();
        }

        // Verify total supply is zero after all withdrawals.
        assertEq(rewarder.totalSupply(), 0);
    }
}
