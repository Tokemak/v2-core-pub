// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { AuraRewards } from "src/libs/AuraRewards.sol";
import { AURA_MAINNET, AURA_BOOSTER } from "test/utils/Addresses.sol";

contract AuraRewardTest is Test {
    using AuraRewards for address;

    // Aura Rewarder for rETH-WETH pool
    address internal constant AURA_REWARDER = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_197_308);
    }

    function testAURARewardHistoric() public {
        // targeting this transaction:
        // https://etherscan.io/tx/0xd6fd72ad7ba7a2530289b77fc48d5b82b3ff2ffc86830829969aab025669d96f
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_197_308);
        uint256 balEarned = 334.110533530897585917e18;
        uint256 expectedAURA = 416.168080566086033015e18;

        uint256 auraAmount = AuraRewards.getAURAMintAmount(AURA_MAINNET, AURA_BOOSTER, AURA_REWARDER, balEarned);

        assertEq(auraAmount, expectedAURA);
    }

    function testAURARewardIfTotalSupplyIsZero() public {
        checkAURAMintAmount(0, 990, 0);
    }

    function testAURARewardIfInCliffs() public {
        uint256 totalSupply = 101_000 * 1e18 + 5e25; // each cliff is 100_000 tokens, so we're in the 1st cliff (zero
            // indexed)
        uint256 balEarned = 898_000;
        uint256 expectedAURA = balEarned * 4 / 10 * 1947 / 500;
        checkAURAMintAmount(totalSupply, balEarned, expectedAURA);
    }

    function testAURARewardIfInLastCliff() public {
        uint256 totalSupply = 99_999_000 * 1e18; // leaves 1000 tokens
        uint256 balEarned = 1001 * 1000 * 1e18; // try to exceed the max supply
        uint256 expectedAURA = 1000 * 1e18; // expect to only get the remaining 1000 tokens, not 1001

        address aura = vm.addr(totalSupply + balEarned);
        vm.mockCall(aura, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));

        uint256 auraAmount = aura.getAURAMintAmount(AURA_BOOSTER, AURA_REWARDER, balEarned);

        assertEq(auraAmount, expectedAURA);
    }

    function checkAURAMintAmount(uint256 totalSupply, uint256 balEarned, uint256 expectedAURAAmount) internal {
        address aura = vm.addr(totalSupply + balEarned);
        vm.mockCall(aura, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));

        uint256 auraAmount = aura.getAURAMintAmount(AURA_BOOSTER, AURA_REWARDER, balEarned);
        assertEq(auraAmount, expectedAURAAmount);
    }
}
