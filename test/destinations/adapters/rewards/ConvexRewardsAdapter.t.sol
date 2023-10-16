// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ConvexRewards } from "src/destinations/adapters/rewards/ConvexRewardsAdapter.sol";
import { CRV_MAINNET, LDO_MAINNET, CNC_MAINNET, CONVEX_BOOSTER, CVX_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract ConvexRewardsAdapterTest is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    IConvexBooster private convexBooster = IConvexBooster(CONVEX_BOOSTER);

    EnumerableSet.AddressSet internal _trackedTokens;

    uint256 private _mainFork;
    string private _endpoint;

    function setUp() public {
        _endpoint = vm.envString("MAINNET_RPC_URL");
        _mainFork = vm.createFork(_endpoint, 16_728_070);
        vm.selectFork(_mainFork);
    }

    function transferCurveLpTokenAndDepositToConvex(address curveLp, address convexPool, address from) private {
        uint256 balance = IERC20(curveLp).balanceOf(from);
        vm.prank(from);
        IERC20(curveLp).transfer(address(this), balance);

        uint256 pid = IBaseRewardPool(convexPool).pid();

        IERC20(curveLp).approve(address(convexBooster), balance);
        convexBooster.deposit(pid, balance, true);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);
    }

    function test_RevertIf_GaugeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gauge"));
        ConvexRewards.claimRewards(address(0), CVX_MAINNET, _trackedTokens);
    }

    function test_RevertIf_SendToIsZero() public {
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "sendTo"));
        ConvexRewards.claimRewards(gauge, CVX_MAINNET, address(0), _trackedTokens);
    }

    // pool ETH-USDC
    function test_claimRewards_RevertIf_AuraClaimFails() public {
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

        bytes4 selector = bytes4(keccak256(bytes("getReward(address,bool)")));
        vm.mockCall(gauge, abi.encodeWithSelector(selector, address(this), true), abi.encode(false));
        vm.expectRevert(RewardAdapter.ClaimRewardsFailed.selector);
        ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);
    }

    // Pool frxETH-ETH
    function test_ETHfrxETH_pool() public {
        address curveLp = 0xf43211935C781D5ca1a41d2041F397B8A7366C7A;
        address curveLpWhale = 0x1577671a75855a3Ffc87a3E7cba597BD5560f149;
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 2);
        assertEq(address(rewardsToken[0]), CRV_MAINNET);
        assertTrue(amountsClaimed[0] > 0);
        assertEq(address(rewardsToken[1]), CVX_MAINNET);
        assertTrue(amountsClaimed[1] > 0);
    }

    // Pool rETH-wstETH
    function test_rETHwstETH_pool() public {
        address curveLp = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
        address curveLpWhale = 0xc3d07A32b57Fd277939E7c83f83fF47e3BE5Cf62;
        address gauge = 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 2);
        assertEq(address(rewardsToken[0]), CRV_MAINNET);
        assertTrue(amountsClaimed[0] > 0);
        assertEq(address(rewardsToken[1]), CVX_MAINNET);
        assertTrue(amountsClaimed[1] > 0);
    }

    // Pool stETH-ETH
    function test_ETHstETH_pool() public {
        address curveLp = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveLpWhale = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
        address gauge = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length, "arrayEq");
        assertEq(rewardsToken.length, 3, "arrayLen");
        assertEq(address(rewardsToken[0]), LDO_MAINNET, "ldo");
        assertTrue(amountsClaimed[0] > 0, "ldoAmount");
        assertEq(address(rewardsToken[1]), CRV_MAINNET, "crv");
        assertTrue(amountsClaimed[1] > 0, "crvAmount");
        assertEq(address(rewardsToken[2]), CVX_MAINNET, "cvx");
        assertTrue(amountsClaimed[2] > 0, "cvxAmount");
    }

    function test_RewardsCapturedWhenClaimedByThirdParty() public {
        address curveLp = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveLpWhale = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
        address gauge = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length, "arrayEq");
        assertEq(rewardsToken.length, 3, "arrayLen");
        assertEq(address(rewardsToken[0]), LDO_MAINNET, "ldo");
        assertTrue(amountsClaimed[0] > 0, "ldoAmount");
        assertEq(address(rewardsToken[1]), CRV_MAINNET, "crv");
        assertTrue(amountsClaimed[1] > 0, "crvAmount");
        assertEq(address(rewardsToken[2]), CVX_MAINNET, "cvx");
        assertTrue(amountsClaimed[2] > 0, "cvxAmount");
    }

    function test_TrackedTokensAreNotReported() public {
        address curveLp = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveLpWhale = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
        address gauge = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        _trackedTokens.add(LDO_MAINNET);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length, "arrayEq");
        assertEq(rewardsToken.length, 3, "arrayLen");
        assertEq(address(rewardsToken[0]), address(0), "ldo");
        assertTrue(amountsClaimed[0] == 0, "ldoAmount");
        assertEq(address(rewardsToken[1]), CRV_MAINNET, "crv");
        assertTrue(amountsClaimed[1] > 0, "crvAmount");
        assertEq(address(rewardsToken[2]), CVX_MAINNET, "cvx");
        assertTrue(amountsClaimed[2] > 0, "cvxAmount");
    }

    function test_TrackedTokensAreNotTransferred() public {
        address curveLp = 0x06325440D014e39736583c165C2963BA99fAf14E;
        address curveLpWhale = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
        address gauge = 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        assertTrue(IERC20(LDO_MAINNET).balanceOf(address(this)) == 0);

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        _trackedTokens.add(LDO_MAINNET);

        address user = address(3);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, user, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length, "arrayEq");
        assertEq(rewardsToken.length, 3, "arrayLen");
        assertEq(address(rewardsToken[0]), address(0), "ldo");
        assertTrue(amountsClaimed[0] == 0, "ldoAmount");
        assertEq(address(rewardsToken[1]), CRV_MAINNET, "crv");
        assertTrue(amountsClaimed[1] > 0, "crvAmount");
        assertEq(address(rewardsToken[2]), CVX_MAINNET, "cvx");
        assertTrue(amountsClaimed[2] > 0, "cvxAmount");

        // LDO was claimed, but it should stay here
        assertEq(IERC20(LDO_MAINNET).balanceOf(user), amountsClaimed[0]);
        assertTrue(IERC20(LDO_MAINNET).balanceOf(address(this)) > 0);
        assertEq(IERC20(CRV_MAINNET).balanceOf(user), amountsClaimed[1]);
        assertEq(IERC20(CVX_MAINNET).balanceOf(user), amountsClaimed[2]);
    }

    function test_StashTokensWithUnderlyingBalanceAreReturned() public {
        // CNC is a stash token with a earning balance
        // CVX is also a stash token but without an earning balance, we just get CVX from the normal mint

        vm.createSelectFork(_endpoint, 18_085_749);

        address curveLp = 0xF9835375f6b268743Ea0a54d742Aa156947f8C06;
        address curveLpWhale = 0xd8c2ee2FEfAc57F8B3cD63bE28D8F89bBBf5a5F2;
        address gauge = 0x1A3c8B2F89B1C2593fa46C30ADA0b4E3D0133fF8;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        address user = address(8);

        (uint256[] memory amountsClaimed, address[] memory rewardTokens) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, user, _trackedTokens);

        assertEq(amountsClaimed.length, rewardTokens.length, "arrayEq");
        assertEq(rewardTokens.length, 4, "arrayLen");

        assertEq(rewardTokens[0], CNC_MAINNET, "cncToken");
        assertEq(rewardTokens[1], CVX_MAINNET, "cvxToken");
        assertEq(rewardTokens[2], CRV_MAINNET, "crvToken");
        assertEq(rewardTokens[3], address(0), "empty");

        assertTrue(amountsClaimed[0] > 0, "cncBal");
        assertTrue(amountsClaimed[1] > 0, "cvxBal");
        assertTrue(amountsClaimed[2] > 0, "crvBal");
        assertTrue(amountsClaimed[3] == 0, "lastBal");

        assertEq(IERC20(rewardTokens[0]).balanceOf(user), amountsClaimed[0]);
        assertEq(IERC20(rewardTokens[1]).balanceOf(user), amountsClaimed[1]);
        assertEq(IERC20(rewardTokens[2]).balanceOf(user), amountsClaimed[2]);

        vm.selectFork(_mainFork);
    }

    function test_NonDefaultStashTokensWithoutUnderlyingBalanceAreNotReturned() public {
        // LDO and CVX are stash tokens without a balance

        vm.createSelectFork(_endpoint, 17_091_889);

        address curveLp = 0x828b154032950C8ff7CF8085D841723Db2696056;
        address curveLpWhale = 0xD1caD198fa57088C01f2B6a8c64273ef6D1eC085;
        address gauge = 0xA61b57C452dadAF252D2f101f5Ba20aA86152992;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        address user = address(8);

        (uint256[] memory amountsClaimed, address[] memory rewardTokens) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, user, _trackedTokens);

        assertEq(amountsClaimed.length, rewardTokens.length, "arrayEq");
        assertEq(rewardTokens.length, 4, "arrayLen");

        assertEq(rewardTokens[0], address(0), "emptyLDOStash"); // Was LDO Stash
        assertEq(rewardTokens[1], CVX_MAINNET, "cvxToken");
        assertEq(rewardTokens[2], CRV_MAINNET, "crvToken");
        assertEq(rewardTokens[3], address(0), "emptyCVXStash"); // Was CVX, but collapsed into stash entry

        assertTrue(amountsClaimed[0] == 0, "ldoStashBal");
        assertTrue(amountsClaimed[1] > 0, "cvxBal");
        assertTrue(amountsClaimed[2] > 0, "crvBal");
        assertTrue(amountsClaimed[3] == 0, "cvxStashBal");

        assertEq(IERC20(rewardTokens[1]).balanceOf(user), amountsClaimed[1]);
        assertEq(IERC20(rewardTokens[2]).balanceOf(user), amountsClaimed[2]);

        vm.selectFork(_mainFork);
    }

    // Pool sETH-ETH
    function test_ETHsETH_pool() public {
        address curveLp = 0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c;
        address curveLpWhale = 0xB289360A2Ab9eacfFd1d7883183A6d9576DB515F;
        address gauge = 0x192469CadE297D6B21F418cFA8c366b63FFC9f9b;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            ConvexRewards.claimRewards(gauge, CVX_MAINNET, _trackedTokens);

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 2);
        assertEq(address(rewardsToken[0]), CRV_MAINNET);
        assertEq(address(rewardsToken[1]), CVX_MAINNET);
        assertTrue(amountsClaimed[0] > 0);
        assertTrue(amountsClaimed[1] > 0);
    }
}
