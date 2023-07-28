// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { CamelotBase } from "test/base/CamelotBase.sol";
import { CamelotRewardsAdapter } from "src/destinations/adapters/rewards/CamelotRewardsAdapter.sol";
import { Errors } from "src/utils/Errors.sol";
import { XGRAIL_ARBITRUM, GRAIL_ARBITRUM } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract CamelotRewardsAdapterTest is CamelotBase {
    IERC20 private grailToken = IERC20(GRAIL_ARBITRUM);
    IERC20 private xGrailToken = IERC20(XGRAIL_ARBITRUM);

    function setUp() public {
        string memory endpoint = vm.envString("ARBITRUM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 65_803_040);
        vm.selectFork(forkId);
    }

    /**
     * @dev Implementing this function is mandatory in calling contract for a proper reward claiming
     */
    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool) {
        return CamelotRewardsAdapter.onNFTHarvest(operator, to, tokenId, grailAmount, xGrailAmount);
    }

    function test_Revert_IfAddressZeroGrailToken() public {
        address nftPoolAddress = 0x6BC938abA940fB828D39Daa23A94dfc522120C11;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "grailToken"));
        CamelotRewardsAdapter.claimRewards(IERC20(address(0)), xGrailToken, nftPoolAddress);
    }

    function test_Revert_IfAddressZeroXGrailToken() public {
        address nftPoolAddress = 0x6BC938abA940fB828D39Daa23A94dfc522120C11;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "xGrailToken"));
        CamelotRewardsAdapter.claimRewards(grailToken, IERC20(address(0)), nftPoolAddress);
    }

    function test_Revert_IfAddressZeroNftPool() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "nftPoolAddress"));
        CamelotRewardsAdapter.claimRewards(grailToken, xGrailToken, address(0));
    }

    // pool ETH-USDC
    function test_claimRewards_PoolETH_USDC() public {
        address whale = 0xEfe609f34A17C919118C086F81d61ecA579AB2E7;
        address nftPoolAddress = 0x6BC938abA940fB828D39Daa23A94dfc522120C11;
        vm.startPrank(whale);
        transferNFTsTo(nftPoolAddress, whale, address(this));
        vm.stopPrank();

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            CamelotRewardsAdapter.claimRewards(grailToken, xGrailToken, nftPoolAddress);

        assertEq(rewardsToken.length, 2);
        assertEq(rewardsToken[0], GRAIL_ARBITRUM);
        assertEq(rewardsToken[1], XGRAIL_ARBITRUM);
        assertEq(amountsClaimed[0] > 0, true);
        assertEq(amountsClaimed[1] > 0, true);
    }

    // pool ETH-wstETH
    function test_claimRewards_PoolWETHwstETH() public {
        address whale = 0xfF2BDf4dbf09175e615f2A27bCF3890B3a29CFf8;
        address nftPoolAddress = 0x32B18B8ccD84983C7ddc14c215A42caC098BA714;

        vm.startPrank(whale);
        transferNFTsTo(nftPoolAddress, whale, address(this));
        vm.stopPrank();

        (uint256[] memory amountsClaimed, address[] memory rewardsToken) =
            CamelotRewardsAdapter.claimRewards(grailToken, xGrailToken, nftPoolAddress);

        assertTrue(rewardsToken.length == 2);
        assertEq(rewardsToken.length, 2);
        assertEq(rewardsToken[0], GRAIL_ARBITRUM);
        assertEq(rewardsToken[1], XGRAIL_ARBITRUM);
        assertEq(amountsClaimed[0] > 0, true);
        assertEq(amountsClaimed[1] > 0, true);
    }
}
