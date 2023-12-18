// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ConvexRewards } from "src/libs/ConvexRewards.sol";
import { CVX_MAINNET } from "test/utils/Addresses.sol";

contract ConvexRewardTest is Test {
    using ConvexRewards for address;

    function testCVXRewardHistoric() public {
        // targeting this transaction:
        // https://etherscan.io/tx/0x46314e9730ef79c43135de478daf04b08acec36095045376f46ec7920daef0bb
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17_580_732);
        uint256 crvEarned = 43_632_695_514_897_054_325;
        uint256 expectedCVX = 698_123_128_238_352_869;

        uint256 cvxAmount = ConvexRewards.getCVXMintAmount(CVX_MAINNET, crvEarned);

        assertEq(cvxAmount, expectedCVX);
    }

    function testCVXRewardIfTotalSupplyIsZero() public {
        checkCVXMintAmount(0, 987, 0);
    }

    function testCVXRewardIfInCliffs() public {
        uint256 totalSupply = 101_000 * 1e18; // each cliff is 100_000 tokens, so we're in the 1st cliff (zero indexed)
        uint256 crvEarned = 898_000;
        uint256 expectedCVX = crvEarned * 999 / 1000;
        checkCVXMintAmount(totalSupply, crvEarned, expectedCVX);
    }

    function testCVXRewardIfInLastCliff() public {
        uint256 totalSupply = 99_999_000 * 1e18; // leaves 1000 tokens
        uint256 crvEarned = 1001 * 1000 * 1e18; // try to exceed the max supply
        uint256 expectedCVX = 1000 * 1e18; // expect to only get the remaining 1000 tokens, not 1001

        address cvx = vm.addr(totalSupply + crvEarned);
        vm.mockCall(cvx, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));

        uint256 cvxAmount = cvx.getCVXMintAmount(crvEarned);

        assertEq(cvxAmount, expectedCVX);
    }

    function checkCVXMintAmount(uint256 totalSupply, uint256 crvEarned, uint256 expectedCVXAmount) internal {
        address cvx = vm.addr(totalSupply + crvEarned);
        vm.mockCall(cvx, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply));

        uint256 cvxAmount = cvx.getCVXMintAmount(crvEarned);

        assertEq(cvxAmount, expectedCVXAmount);
    }
}
