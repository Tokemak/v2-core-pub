// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
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
        address whale = 0xb312665792d45A3884e605e8B7626aD5b09D66a1;
        address pool = 0x497139e8435E01555AC1e3740fccab7AFf149e02;

        vm.startPrank(whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        AerodromeRewardsAdapter.claimRewards(IVoter(address(0)), pool, whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        AerodromeRewardsAdapter.claimRewards(voter, address(0), whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whale"));
        AerodromeRewardsAdapter.claimRewards(voter, pool, address(0));

        vm.stopPrank();
    }

    // ezETH/WETH (stable pool)
    function test_claimRewards_Pool_sEzETHwETH() public {
        address whale = 0xb312665792d45A3884e605e8B7626aD5b09D66a1;
        address pool = 0x497139e8435E01555AC1e3740fccab7AFf149e02;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    // ezETH/WETH (volatile pool)
    function test_claimRewards_Pool_vEzETHwETH() public {
        address whale = 0x96219Af7616187Af0Bab5e22a5D2503efc6D2904;
        address pool = 0x0C8bF3cb3E1f951B284EF14aa95444be86a33E2f;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    // weETH/WETH (volatile pool)
    function test_claimRewards_Pool_vWeETHwETH() public {
        address whale = 0x7c12CD5b7Db841f7Ba9B3fd1B7a6D02C1304386d;
        address pool = 0x91F0f34916Ca4E2cCe120116774b0e4fA0cdcaA8;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    // cbETH/WETH (volatile pool)
    function test_claimRewards_Pool_vCbETHwETH() public {
        address whale = 0x402bb6A5ed277E2b4B394b37f5d6692B24C9720f;
        address pool = 0x44Ecc644449fC3a9858d2007CaA8CFAa4C561f91;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    // WETH/rETH (volatile pool)
    function test_claimRewards_Pool_vWethReth() public {
        address whale = 0x90F2cd3fdc5Ad13Fd4347Bc342A236F7c40b0Dc2;
        address pool = 0xA6F8A6bc3deA678d5bA786f2Ad2f5F93d1c87c18;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }

    // WETH/wstETH (volatile pool)
    function test_claimRewards_Pool_vWethWstEth() public {
        address whale = 0x3c74c735b5863C0baF52598d8Fd2D59611c8320F;
        address pool = 0xA6385c73961dd9C58db2EF0c4EB98cE4B60651e8;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            AerodromeRewardsAdapter.claimRewards(voter, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 1);

        assertEq(address(rewardsToken[0]), AERO_BASE);

        assertTrue(amountsClaimed[0] > 0);
    }
}
