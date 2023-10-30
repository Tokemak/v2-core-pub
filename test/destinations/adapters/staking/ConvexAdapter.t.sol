// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ConvexStaking } from "src/destinations/adapters/staking/ConvexAdapter.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { CONVEX_BOOSTER } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract ConvexAdapterTest is Test {
    IConvexBooster private convexBooster = IConvexBooster(CONVEX_BOOSTER);

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 16_728_070);
        vm.selectFork(forkId);
    }

    function transferCurveLpTokenAndDepositToConvex(
        address curveLp,
        address convexPool,
        uint256 balance,
        address from
    ) private {
        vm.prank(from);
        IERC20(curveLp).transfer(address(this), balance);

        uint256 pid = IBaseRewardPool(convexPool).pid();

        ConvexStaking.depositAndStake(convexBooster, curveLp, convexPool, pid, balance);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);
    }

    function test_RevertIf_PoolIsShutdown() public {
        address curveLp = 0xf43211935C781D5ca1a41d2041F397B8A7366C7A;
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector),
            abi.encode(curveLp, address(0), address(0), gauge, address(0), true)
        );
        vm.expectRevert(abi.encodeWithSelector(ConvexStaking.PoolShutdown.selector));
        ConvexStaking.depositAndStake(convexBooster, curveLp, gauge, 0, 10);
    }

    // Pool frxETH-ETH
    function test_ETHfrxETH_pool() public {
        address curveLp = 0xf43211935C781D5ca1a41d2041F397B8A7366C7A;
        address curveLpWhale = 0x1577671a75855a3Ffc87a3E7cba597BD5560f149;
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

        // Deposit
        uint256 balance = IERC20(curveLp).balanceOf(curveLpWhale);
        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, balance, curveLpWhale);

        // Withdraw
        ConvexStaking.withdrawStake(curveLp, gauge, balance);
        assertEq(balance, IERC20(curveLp).balanceOf(address(this)));
    }

    // Pool rETH-wstETH
    function test_rETHwstETH_pool() public {
        address curveLp = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveLpWhale = 0xc3d07A32b57Fd277939E7c83f83fF47e3BE5Cf62;
        address gauge = 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc;

        // Deposit
        uint256 balance = IERC20(curveLp).balanceOf(curveLpWhale);
        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, balance, curveLpWhale);

        // Withdraw
        ConvexStaking.withdrawStake(curveLp, gauge, balance);
        assertEq(balance, IERC20(curveLp).balanceOf(address(this)));
    }

    // Pool stETH-ETH
    function test_ETHstETH_pool() public {
        address curveLp = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveLpWhale = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
        address gauge = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

        // Deposit
        uint256 balance = IERC20(curveLp).balanceOf(curveLpWhale);
        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, balance, curveLpWhale);

        // Withdraw
        ConvexStaking.withdrawStake(curveLp, gauge, balance);
        assertEq(balance, IERC20(curveLp).balanceOf(address(this)));
    }

    // Pool sETH-ETH
    function test_ETHsETH_pool() public {
        address curveLp = 0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c;
        address curveLpWhale = 0xB289360A2Ab9eacfFd1d7883183A6d9576DB515F;
        address gauge = 0x192469CadE297D6B21F418cFA8c366b63FFC9f9b;

        // Deposit
        uint256 balance = IERC20(curveLp).balanceOf(curveLpWhale);
        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, balance, curveLpWhale);

        // Withdraw
        ConvexStaking.withdrawStake(curveLp, gauge, balance);
        assertEq(balance, IERC20(curveLp).balanceOf(address(this)));
    }
}
