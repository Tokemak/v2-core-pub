// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ConvexArbitrumRewardsAdapter } from "src/destinations/adapters/rewards/ConvexArbitrumRewardsAdapter.sol";
import { IConvexBoosterArbitrum } from "src/interfaces/external/convex/IConvexBoosterArbitrum.sol";
import { IConvexRewardPool } from "src/interfaces/external/convex/IConvexRewardPool.sol";
import { Errors } from "src/utils/Errors.sol";
import { CRV_ARBITRUM, CVX_ARBITRUM, CONVEX_BOOSTER } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract ConvexArbitrumRewardsAdapterTest is Test {
    IConvexBoosterArbitrum private convexBooster = IConvexBoosterArbitrum(CONVEX_BOOSTER);

    function setUp() public {
        string memory endpoint = vm.envString("ARBITRUM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 65_506_618);
        vm.selectFork(forkId);
    }

    function test_Revert_IfAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gauge"));
        ConvexArbitrumRewardsAdapter.claimRewards(address(0));
    }

    function transferCurveLpTokenAndDepositToConvex(
        address curveLp,
        address convexPool,
        address from,
        address to
    ) private {
        uint256 balance = IERC20(curveLp).balanceOf(from);
        vm.prank(from);
        IERC20(curveLp).transfer(to, balance);

        uint256 pid = IConvexRewardPool(convexPool).convexPoolId();

        vm.startPrank(to);
        IERC20(curveLp).approve(address(convexBooster), balance);
        convexBooster.deposit(pid, balance);
        vm.stopPrank();

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);
    }

    // Pool USDT + WBTC + WETH
    function test_claimRewards_PoolUSDTWBTCWETH() public {
        address curveLp = 0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2;
        address curveLpWhale = 0x279818c822E5c6135D989Df50d0bBA96e9564cE5;
        address gauge = 0x90927a78ad13C0Ec9ACf546cE0C16248A7E7a86D;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale, address(this));

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexArbitrumRewardsAdapter.claimRewards(gauge);

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 2);
        assertEq(rewardsToken[0], CRV_ARBITRUM);
        assertEq(rewardsToken[1], CVX_ARBITRUM);
        assertEq(amountsClaimed[0] > 0, true);
        assertEq(amountsClaimed[1], 0);
    }

    // Pool USDC + USDT
    function test_claimRewards_PoolUSDCUSDT() public {
        address curveLp = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
        address curveLpWhale = 0xbF7E49483881C76487b0989CD7d9A8239B20CA41;
        address gauge = 0x63F00F688086F0109d586501E783e33f2C950e78;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale, address(this));

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexArbitrumRewardsAdapter.claimRewards(gauge);

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 2);
        assertEq(rewardsToken[0], CRV_ARBITRUM);
        assertEq(rewardsToken[1], CVX_ARBITRUM);
        assertTrue(amountsClaimed[0] > 0);
        assertEq(amountsClaimed[1], 0);
    }
}
