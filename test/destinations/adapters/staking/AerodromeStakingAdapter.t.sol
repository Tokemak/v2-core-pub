// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { IAerodromeGauge } from "src/interfaces/external/aerodrome/IAerodromeGauge.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { AerodromeStakingAdapter } from "src/destinations/adapters/staking/AerodromeStakingAdapter.sol";
import { AERODROME_VOTER_BASE } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract AerodromeStakingAdapterTest is Test {
    IVoter private voter;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 15_059_513);

        voter = IVoter(AERODROME_VOTER_BASE);
    }

    function test_Revert_On_Zero_Addresses() public {
        address pool = 0x497139e8435E01555AC1e3740fccab7AFf149e02;

        IERC20 lpToken = IERC20(pool);
        deal(address(lpToken), address(this), 10 * 1e18);

        uint256 stakeAmount = lpToken.balanceOf(address(this));
        uint256 lpBalance = 1;
        uint256 minLpMintAmount = 1;

        // Stake LPs

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        AerodromeStakingAdapter.stakeLPs(IVoter(address(0)), stakeAmount, minLpMintAmount, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amount"));
        AerodromeStakingAdapter.stakeLPs(voter, 0, minLpMintAmount, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "minLpMintAmount"));
        AerodromeStakingAdapter.stakeLPs(voter, stakeAmount, 0, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        AerodromeStakingAdapter.stakeLPs(voter, stakeAmount, minLpMintAmount, address(0));

        // Unstake LPs

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        AerodromeStakingAdapter.unstakeLPs(IVoter(address(0)), stakeAmount, lpBalance, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "amount"));
        AerodromeStakingAdapter.unstakeLPs(voter, 0, lpBalance, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "maxLpBurnAmount"));
        AerodromeStakingAdapter.unstakeLPs(voter, stakeAmount, 0, pool);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        AerodromeStakingAdapter.unstakeLPs(voter, stakeAmount, lpBalance, address(0));
    }

    function test_Staking_Unstaking_On_Pools() public {
        // ezETH/WETH (stable pool)
        verifyStakingUnstakingOnPool(0x497139e8435E01555AC1e3740fccab7AFf149e02);

        // ezETH/WETH (volatile pool)
        verifyStakingUnstakingOnPool(0x0C8bF3cb3E1f951B284EF14aa95444be86a33E2f);

        // weETH/WETH (volatile pool)
        verifyStakingUnstakingOnPool(0x91F0f34916Ca4E2cCe120116774b0e4fA0cdcaA8);

        // cbETH/WETH (volatile pool)
        verifyStakingUnstakingOnPool(0x44Ecc644449fC3a9858d2007CaA8CFAa4C561f91);

        // WETH/rETH (volatile pool)
        verifyStakingUnstakingOnPool(0xA6F8A6bc3deA678d5bA786f2Ad2f5F93d1c87c18);

        // WETH/wstETH (volatile pool)
        verifyStakingUnstakingOnPool(0xA6385c73961dd9C58db2EF0c4EB98cE4B60651e8);
    }

    function verifyStakingUnstakingOnPool(address pool) public {
        IERC20 lpToken = IERC20(pool);
        deal(address(lpToken), address(this), 10 * 1e18);

        // Stake LPs
        uint256 minLpMintAmount = 1;

        IAerodromeGauge gauge = IAerodromeGauge(voter.gauges(pool));
        uint256 preStakeLpBalance = gauge.balanceOf(address(this));

        uint256 stakeAmount = lpToken.balanceOf(address(this));
        AerodromeStakingAdapter.stakeLPs(voter, stakeAmount, minLpMintAmount, pool);

        uint256 afterStakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterStakeLpBalance > 0 && afterStakeLpBalance > preStakeLpBalance);

        // Unstake LPs
        AerodromeStakingAdapter.unstakeLPs(voter, stakeAmount, afterStakeLpBalance, pool);

        uint256 afterUnstakeLpBalance = gauge.balanceOf(address(this));

        assertTrue(afterUnstakeLpBalance == preStakeLpBalance);
    }
}
