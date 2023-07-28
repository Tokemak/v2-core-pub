// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { BeethovenRewardsAdapter } from "src/destinations/adapters/rewards/BeethovenRewardsAdapter.sol";
import { IChildChainGaugeRewardHelper } from "src/interfaces/external/beethoven/IChildChainGaugeRewardHelper.sol";

// solhint-disable func-name-mixedcase
contract BeethovenRewardsAdapterTest is Test {
    IChildChainGaugeRewardHelper private gaugeRewardHelper =
        IChildChainGaugeRewardHelper(0x299dcDF14350999496204c141A0c20A29d71AF3E);

    function setUp() public {
        string memory endpoint = vm.envString("OPTIMISM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 76_328_272);
        vm.selectFork(forkId);
    }

    function test_Revert_IfGaugeRewardHelperAddressZero() public {
        address gauge = 0x6341B7472152D7b7F9af3158C6A42349a2cA6c72;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gaugeRewardHelper"));
        BeethovenRewardsAdapter.claimRewards(IChildChainGaugeRewardHelper(address(0)), gauge);
    }

    function test_Revert_IfGaugeAddressZero() public {
        address gauge = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "gauge"));
        BeethovenRewardsAdapter.claimRewards(gaugeRewardHelper, gauge);
    }

    // Shanghai Shakedown wstETH-WETH
    function test_claimRewards_PoolwstETHWETH() public {
        address gauge = 0x6341B7472152D7b7F9af3158C6A42349a2cA6c72;
        address whale = 0x7B88DF8AF7a283e3dc84A7Fd97Fde19cAbb90eD4;

        uint256 gaugeBalance = IERC20(gauge).balanceOf(whale);
        vm.prank(whale);
        IERC20(gauge).transfer(address(this), gaugeBalance);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            BeethovenRewardsAdapter.claimRewards(gaugeRewardHelper, gauge);

        assertEq(rewardsToken.length, 3);
        assertEq(rewardsToken[0], 0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921);
        assertEq(rewardsToken[1], 0x4200000000000000000000000000000000000042);
        assertEq(rewardsToken[2], 0xFdb794692724153d1488CcdBE0C56c252596735F);
        assertEq(amountsClaimed[0], 0);
        assertEq(amountsClaimed[1], 17_234_439_874_813_647);
        assertEq(amountsClaimed[2], 15_565_787_459_188_619);
    }

    // Rocket Fuel WETH-rETH
    function test_claimRewards_PoolWETHrETH() public {
        address gauge = 0x38f79beFfC211c6c439b0A3d10A0A673EE63AFb4;
        address whale = 0x3EaBa81dCdD9dFb51510ABB2C0e976Ab041F7a0d;

        uint256 gaugeBalance = IERC20(gauge).balanceOf(whale);

        vm.prank(whale);
        IERC20(gauge).transfer(address(this), gaugeBalance);

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            BeethovenRewardsAdapter.claimRewards(gaugeRewardHelper, gauge);

        assertEq(rewardsToken.length, 2);
        assertEq(rewardsToken[0], 0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921);
        assertEq(rewardsToken[1], 0x4200000000000000000000000000000000000042);
        assertEq(amountsClaimed[0], 39_767_520_355_511_914);
        assertEq(amountsClaimed[1], 1_119_177_248_878_167_643);
    }
}
