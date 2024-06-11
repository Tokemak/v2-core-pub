// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { AerodromeStakingAdapter } from "src/destinations/adapters/staking/AerodromeStakingAdapter.sol";
import { AerodromeRewardsAdapter } from "src/destinations/adapters/rewards/AerodromeRewardsAdapter.sol";

import { AERODROME_VOTER_BASE, AERO_BASE } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract AerodromeRewardsAdapterTest is Test {
    IVoter private voter;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 15_059_513);

        vm.label(address(this), "AerodromeRewardsAdapterTest");

        voter = IVoter(AERODROME_VOTER_BASE);
    }

    function test_Revert_IfAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gauge"));
        AerodromeRewardsAdapter.claimRewards(address(0), address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "claimFor"));
        AerodromeRewardsAdapter.claimRewards(address(this), address(0));
    }

    // ezETH/WETH (stable pool)
    function test_claimRewards_Pool_sEzETHwETH() public {
        _verifyPool(0x497139e8435E01555AC1e3740fccab7AFf149e02);
    }

    // ezETH/WETH (volatile pool)
    function test_claimRewards_Pool_vEzETHwETH() public {
        _verifyPool(0x0C8bF3cb3E1f951B284EF14aa95444be86a33E2f);
    }

    // weETH/WETH (volatile pool)
    function test_claimRewards_Pool_vWeETHwETH() public {
        _verifyPool(0x91F0f34916Ca4E2cCe120116774b0e4fA0cdcaA8);
    }

    // cbETH/WETH (volatile pool)
    function test_claimRewards_Pool_vCbETHwETH() public {
        _verifyPool(0x44Ecc644449fC3a9858d2007CaA8CFAa4C561f91);
    }

    // WETH/rETH (volatile pool)
    function test_claimRewards_Pool_vWethReth() public {
        _verifyPool(0xA6F8A6bc3deA678d5bA786f2Ad2f5F93d1c87c18);
    }

    // WETH/wstETH (volatile pool)
    function test_claimRewards_Pool_vWethWstEth() public {
        _verifyPool(0xA6385c73961dd9C58db2EF0c4EB98cE4B60651e8);
    }

    function _verifyPool(address pool) private {
        
        address gauge = _getGaugeForPool(pool);
        _stakeForRewards(pool, gauge);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(gauge, address(this));

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    function _stakeForRewards(address pool, address gauge) private {
        IERC20 lpToken = IERC20(pool);
        deal(address(lpToken), address(this), 10 * 1e18);

        // Stake LPs
        uint256 stakeAmount = lpToken.balanceOf(address(this));
        AerodromeStakingAdapter.stakeLPs(gauge, stakeAmount);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);
    }

    function _getGaugeForPool(address pool) private view returns (address) {
      return voter.gauges(pool);
    }
}
