// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { MaverickRewardsAdapter } from "src/destinations/adapters/rewards/MaverickRewardsAdapter.sol";
import {
    LDO_MAINNET, MAV_WSTETH_WETH_BOOSTED_POS, MAV_WSTETH_WETH_BOOSTED_POS_REWARDER
} from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract MaverickRewardsAdapterTest is Test {
    address private constant REWARDER = MAV_WSTETH_WETH_BOOSTED_POS_REWARDER;
    IERC20 private constant STAKING_TOKEN = IERC20(MAV_WSTETH_WETH_BOOSTED_POS);

    function _stakeForAdapter(uint256 amount) internal {
        deal(address(STAKING_TOKEN), address(this), amount);

        STAKING_TOKEN.approve(address(REWARDER), amount);
        IReward(REWARDER).stake(amount, address(this));

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_360_127);
    }

    function test_Revert_IfAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rewarder"));
        MaverickRewardsAdapter.claimRewards(address(0));
    }

    function test_claimRewards_Successful() public {
        _stakeForAdapter(1e18);
        uint256 ldoBefore = IERC20(LDO_MAINNET).balanceOf(address(this));
        (uint256[] memory amts, address[] memory tokens) = MaverickRewardsAdapter.claimRewards(REWARDER);
        // check based on previous execution
        assertEq(tokens.length, 2);
        assertEq(address(tokens[1]), LDO_MAINNET);
        assertTrue(amts[1] > 0);
        assertEq(IERC20(LDO_MAINNET).balanceOf(address(this)) - ldoBefore, amts[1]);
    }

    function test_claimRewards_TransfersToSpecifiedAddress() public {
        _stakeForAdapter(1e18);
        address receiver = vm.addr(34);
        uint256 ldoBefore = IERC20(LDO_MAINNET).balanceOf(receiver);
        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            MaverickRewardsAdapter.claimRewards(REWARDER, receiver);
        // check based on previous execution
        assertEq(rewardsToken.length, 2);
        assertEq(address(rewardsToken[1]), LDO_MAINNET);
        assertTrue(amountsClaimed[1] > 0);
        assertEq(IERC20(LDO_MAINNET).balanceOf(receiver) - ldoBefore, amountsClaimed[1]);
    }

    function test_claimRewards_Revert_IfMoreThanMaxUint8EarnedInfoArray() public {
        IReward.EarnedInfo[] memory fakeEarnedInfo = new IReward.EarnedInfo[](256); // Over max uint8.

        // Mock `IReward.earned()` call.
        vm.mockCall(
            REWARDER,
            abi.encodeWithSignature("earned(address)"), // One call, calling account doesn't matter
            abi.encode(fakeEarnedInfo)
        );

        vm.expectRevert(); // Overflowing uint8, max 255.
        MaverickRewardsAdapter.claimRewards(REWARDER, address(this));
    }
}
