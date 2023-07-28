// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { IVoter } from "src/interfaces/external/velodrome/IVoter.sol";
import { IVotingEscrow } from "src/interfaces/external/velodrome/IVotingEscrow.sol";
import { IWrappedExternalBribeFactory } from "src/interfaces/external/velodrome/IWrappedExternalBribeFactory.sol";
import { IRewardsDistributor } from "src/interfaces/external/velodrome/IRewardsDistributor.sol";
import { VelodromeRewardsAdapter } from "src/destinations/adapters/rewards/VelodromeRewardsAdapter.sol";
import { IChildChainGaugeRewardHelper } from "src/interfaces/external/beethoven/IChildChainGaugeRewardHelper.sol";
import {
    USDC_OPTIMISM,
    SUSDC_OPTIMISM,
    VELO_OPTIMISM,
    OP_OPTIMISM,
    OPTI_DOGE_OPTIMISM,
    WSTETH_OPTIMISM,
    USDT_OPTIMISM,
    SONNE_OPTIMISM,
    WETH9_OPTIMISM,
    RETH_OPTIMISM
} from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract VelodromeRewardsAdapterTest is Test {
    IChildChainGaugeRewardHelper private gaugeRewardHelper =
        IChildChainGaugeRewardHelper(0x299dcDF14350999496204c141A0c20A29d71AF3E);

    IVoter private voter;
    IWrappedExternalBribeFactory private factory;
    IVotingEscrow private votingEscrow;
    IRewardsDistributor private rewardsDistributor;

    function setUp() public {
        string memory endpoint = vm.envString("OPTIMISM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 86_937_163);
        vm.selectFork(forkId);

        vm.label(address(this), "VelodromeRewardsAdapterTest");

        voter = IVoter(0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e);
        factory = IWrappedExternalBribeFactory(0xFC1AA395EBd27664B11fC093C07E10FF00f0122C);
        votingEscrow = IVotingEscrow(0x9c7305eb78a432ced5C4D14Cac27E8Ed569A2e26);
        rewardsDistributor = IRewardsDistributor(0x5d5Bea9f0Fc13d967511668a60a3369fD53F784F);
    }

    function test_Revert_IfAddressZero() public {
        address whale = 0xC6602A0eE4e10d22C01144747B91365FCE19a59a;
        address pool = 0xd16232ad60188B68076a235c65d692090caba155;

        vm.startPrank(whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "voter"));
        VelodromeRewardsAdapter.claimRewards(IVoter(address(0)), factory, votingEscrow, pool, whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "factory"));
        IWrappedExternalBribeFactory zeroFactory = IWrappedExternalBribeFactory(address(0));
        VelodromeRewardsAdapter.claimRewards(voter, zeroFactory, votingEscrow, pool, whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "votingEscrow"));
        VelodromeRewardsAdapter.claimRewards(voter, factory, IVotingEscrow(address(0)), pool, whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        VelodromeRewardsAdapter.claimRewards(voter, factory, votingEscrow, address(0), whale);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whale"));
        VelodromeRewardsAdapter.claimRewards(voter, factory, votingEscrow, pool, address(0));

        vm.stopPrank();
    }

    // USDC/sUSD
    function test_claimRewards_PoolUSDCSUSD() public {
        address whale = 0xC6602A0eE4e10d22C01144747B91365FCE19a59a;
        address pool = 0xd16232ad60188B68076a235c65d692090caba155;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            VelodromeRewardsAdapter.claimRewards(voter, factory, votingEscrow, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 8);

        assertEq(address(rewardsToken[0]), USDC_OPTIMISM);
        assertEq(address(rewardsToken[1]), SUSDC_OPTIMISM);
        assertEq(address(rewardsToken[2]), VELO_OPTIMISM);
        assertEq(address(rewardsToken[3]), OP_OPTIMISM);
        assertEq(address(rewardsToken[4]), OPTI_DOGE_OPTIMISM);
        assertEq(address(rewardsToken[5]), WSTETH_OPTIMISM);
        assertEq(address(rewardsToken[6]), USDT_OPTIMISM);
        assertEq(address(rewardsToken[7]), SONNE_OPTIMISM);

        assertTrue(amountsClaimed[0] > 0);
        assertTrue(amountsClaimed[1] > 0);
        assertTrue(amountsClaimed[2] > 0);
        assertTrue(amountsClaimed[3] > 0);
        assertEq(amountsClaimed[4], 0);
        assertEq(amountsClaimed[5], 0);
        assertEq(amountsClaimed[6], 0);
        assertEq(amountsClaimed[7], 0);
    }

    // WETH/rETH
    function test_claimRewards_PoolWETHRETH() public {
        address whale = 0x43ccfb70ca135cd213FBAF2020B9cCa05F4482E5;
        address pool = 0x985612ff2C9409174FedcFf23d4F4761AF124F88;

        vm.startPrank(whale);

        (uint256[] memory amountsClaimed, IERC20[] memory rewardsToken) =
            VelodromeRewardsAdapter.claimRewards(voter, factory, votingEscrow, pool, whale);

        vm.stopPrank();

        assertEq(amountsClaimed.length, rewardsToken.length);
        assertEq(rewardsToken.length, 5);

        assertEq(address(rewardsToken[0]), WETH9_OPTIMISM);
        assertEq(address(rewardsToken[1]), RETH_OPTIMISM);
        assertEq(address(rewardsToken[2]), VELO_OPTIMISM);
        assertEq(address(rewardsToken[3]), OP_OPTIMISM);
        assertEq(address(rewardsToken[4]), OPTI_DOGE_OPTIMISM);

        assertEq(amountsClaimed[0], 0);
        assertEq(amountsClaimed[1], 0);
        assertTrue(amountsClaimed[2] > 0);
        assertEq(amountsClaimed[3], 0);
        assertEq(amountsClaimed[4], 0);
    }
}
