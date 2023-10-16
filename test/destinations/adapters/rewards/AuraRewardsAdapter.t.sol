// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { AuraRewards } from "src/destinations/adapters/rewards/AuraRewardsAdapter.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { AURA_BOOSTER, BAL_MAINNET, LDO_MAINNET, AURA_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract AuraRewardsAdapterTest is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    IConvexBooster private convexBooster = IConvexBooster(AURA_BOOSTER);

    EnumerableSet.AddressSet internal _trackedTokens;

    string private _endpoint;
    uint256 private _forkId;

    function setUp() public {
        _endpoint = vm.envString("MAINNET_RPC_URL");
        _forkId = vm.createFork(_endpoint, 16_731_638);
        vm.selectFork(_forkId);
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

    function test_claimRewards_RevertIf_ConvexClaimFails() public {
        address gauge = 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4;

        bytes4 selector = bytes4(keccak256(bytes("getReward(address,bool)")));
        vm.mockCall(gauge, abi.encodeWithSelector(selector, address(this), true), abi.encode(false));
        vm.expectRevert(RewardAdapter.ClaimRewardsFailed.selector);
        AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);
    }

    function test_RevertIf_GaugeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gauge"));
        AuraRewards.claimRewards(address(0), AURA_MAINNET, _trackedTokens);
    }

    function test_RevertIf_SendToIsZero() public {
        address gauge = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "sendTo"));
        AuraRewards.claimRewards(gauge, AURA_MAINNET, address(0), _trackedTokens);
    }

    //Pool rETH-WETH
    function test_claimRewards_PoolrETHWETH() public {
        address gauge = 0x001B78CEC62DcFdc660E06A91Eb1bC966541d758;
        address curveLp = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        address curveLpWhale = 0x5f98718e4e0EFcb7B5551E2B2584E6781ceAd867;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), BAL_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
    }

    // Pool wstETH-cbETH
    function test_claimRewards_PoolwstETHcbETH() public {
        address gauge = 0xe35ae62Ff773D518172d4B0b1af293704790B670;

        address curveLp = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        address curveLpWhale = 0x854B004700885A61107B458f11eCC169A019b764;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), BAL_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
    }

    // Pool wstETH-srfxETH-rETH
    function test_claimRewards_PoolwstETHsrfxETHrETH() public {
        address gauge = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;

        address curveLp = 0x5aEe1e99fE86960377DE9f88689616916D5DcaBe;
        address curveLpWhale = 0x854B004700885A61107B458f11eCC169A019b764;

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), BAL_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
    }

    function test_RewardsCapturedWhenClaimedByThirdParty() public {
        address gauge = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;
        address curveLp = 0x5aEe1e99fE86960377DE9f88689616916D5DcaBe;
        address curveLpWhale = 0x854B004700885A61107B458f11eCC169A019b764;

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), BAL_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
    }

    function test_TrackedTokensAreNotReported() public {
        address gauge = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;
        address curveLp = 0x5aEe1e99fE86960377DE9f88689616916D5DcaBe;
        address curveLpWhale = 0x854B004700885A61107B458f11eCC169A019b764;

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        _trackedTokens.add(BAL_MAINNET);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), address(0));
        assertTrue(claimed[0] == 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
    }

    function test_TrackedTokensAreNotTransferred() public {
        address gauge = 0xd26948E7a0223700e3C3cdEA21cA2471abCb8d47;
        address curveLp = 0x5aEe1e99fE86960377DE9f88689616916D5DcaBe;
        address curveLpWhale = 0x854B004700885A61107B458f11eCC169A019b764;

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        _trackedTokens.add(BAL_MAINNET);

        address user = address(3);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, user, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), address(0));
        assertTrue(claimed[0] == 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);

        assertEq(IERC20(BAL_MAINNET).balanceOf(user), claimed[0]);
        assertEq(IERC20(AURA_MAINNET).balanceOf(user), claimed[1]);
    }

    function test_StashTokensWithUnderlyingBalanceAreReturned() public {
        vm.createSelectFork(_endpoint, 18_033_699);

        address gauge = 0xdC38CCAc2008547275878F5D89B642DA27910739;
        address curveLp = 0x20a61B948E33879ce7F23e535CC7BAA3BC66c5a9;
        address curveLpWhale = 0xA4494422A6a3eAaD0De5F2a2160dfCb2f61C8699;

        // IBaseRewardPool rewards = IBaseRewardPool(gauge);
        // rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        address user = address(8);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, user, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 4);
        assertEq(address(tokens[0]), LDO_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
        assertEq(address(tokens[2]), BAL_MAINNET);
        assertTrue(claimed[2] > 0);
        assertEq(address(tokens[3]), address(0)); // Aura is stash token so the Aura mint is collapsed into the previous
        assertTrue(claimed[3] == 0);

        assertEq(IERC20(tokens[0]).balanceOf(user), claimed[0]);
        assertEq(IERC20(tokens[1]).balanceOf(user), claimed[1]);
        assertEq(IERC20(tokens[2]).balanceOf(user), claimed[2]);

        vm.selectFork(_forkId);
    }

    function test_NonDefaultStashTokensWithoutUnderlyingBalanceAreNotReturned() public {
        vm.createSelectFork(_endpoint, 18_128_396);

        address gauge = 0x646E272dA2766Bdfd8079643Ffbb30830Fb87303;
        address curveLp = 0x37b18B10ce5635a84834b26095A0AE5639dCB752;
        address curveLpWhale = 0xce88686553686DA562CE7Cea497CE749DA109f9F;

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        address user = address(8);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, user, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 4);
        assertEq(address(tokens[0]), AURA_MAINNET); // Aura stash
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), address(0)); // SD stash but empty
        assertTrue(claimed[1] == 0);
        assertEq(address(tokens[2]), BAL_MAINNET);
        assertTrue(claimed[2] > 0);
        assertEq(address(tokens[3]), address(0)); // Was Aura but pulled into 0 spot
        assertTrue(claimed[3] == 0);

        assertEq(IERC20(tokens[0]).balanceOf(user), claimed[0]);
        assertEq(IERC20(tokens[2]).balanceOf(user), claimed[2]);

        vm.selectFork(_forkId);
    }

    function test_StashTokensWithUnderlyingBalanceAreReturnedWithPreClaim() public {
        vm.createSelectFork(_endpoint, 18_033_699);

        address gauge = 0xdC38CCAc2008547275878F5D89B642DA27910739;
        address curveLp = 0x20a61B948E33879ce7F23e535CC7BAA3BC66c5a9;
        address curveLpWhale = 0xA4494422A6a3eAaD0De5F2a2160dfCb2f61C8699;

        IBaseRewardPool rewards = IBaseRewardPool(gauge);
        rewards.getReward(address(this), true);

        transferCurveLpTokenAndDepositToConvex(curveLp, gauge, curveLpWhale);

        address user = address(8);

        (uint256[] memory claimed, address[] memory tokens) =
            AuraRewards.claimRewards(gauge, AURA_MAINNET, user, _trackedTokens);

        assertEq(claimed.length, tokens.length);
        assertEq(tokens.length, 4);
        assertEq(address(tokens[0]), LDO_MAINNET);
        assertTrue(claimed[0] > 0);
        assertEq(address(tokens[1]), AURA_MAINNET);
        assertTrue(claimed[1] > 0);
        assertEq(address(tokens[2]), BAL_MAINNET);
        assertTrue(claimed[2] > 0);
        assertEq(address(tokens[3]), address(0)); // Aura is stash token so the Aura mint is collapsed into the previous
        assertTrue(claimed[3] == 0);

        vm.selectFork(_forkId);
    }
}

library TestAuraAdapter {
    function claimRewards(
        address gauge,
        address user,
        EnumerableSet.AddressSet storage trackedTokens
    ) internal returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = AuraRewards.claimRewards(gauge, AURA_MAINNET, user, trackedTokens);
    }
}
