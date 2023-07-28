// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/utils/Errors.sol";
import { INFTPool } from "src/interfaces/external/camelot/INFTPool.sol";
import { RewardAdapter } from "src/destinations/adapters/rewards/RewardAdapter.sol";

/**
 * @dev Calling contract should implement `onNFTHarvest` function with the same signature as present in the library.
 * `onNFTHarvest` library function can be wrapped by the caller for a proper work of rewards claiming.
 */
library CamelotRewardsAdapter {
    error WrongOperator(address expected, address actual);
    error WrongTo(address expected, address actual);

    event OnNFTHarvest(address operator, address to, uint256 tokenId, uint256 grailAmount, uint256 xGrailAmount);

    /**
     * @notice Gets rewards from the given NFT pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param grailToken 1st reward token address
     * @param xGrailToken 2nd reward token address
     * @param nftPoolAddress The NFT pool to claim rewards from
     * @return amountsClaimed Quantity of reward tokens received
     * @return rewardTokens Addresses of received reward tokens
     */
    function claimRewards(
        IERC20 grailToken,
        IERC20 xGrailToken,
        address nftPoolAddress
    ) public returns (uint256[] memory amountsClaimed, address[] memory rewardTokens) {
        Errors.verifyNotZero(address(grailToken), "grailToken");
        Errors.verifyNotZero(address(xGrailToken), "xGrailToken");
        Errors.verifyNotZero(nftPoolAddress, "nftPoolAddress");

        address account = address(this);

        INFTPool nftPool = INFTPool(nftPoolAddress);

        uint256 grailTokenBalanceBefore = grailToken.balanceOf(account);
        uint256 xGrailTokenBalanceBefore = xGrailToken.balanceOf(account);

        // get the length of positions NFTs
        uint256 length = nftPool.balanceOf(account);

        // harvest all positions
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = nftPool.tokenOfOwnerByIndex(account, i);
            nftPool.harvestPosition(tokenId);
        }

        uint256 grailTokenBalanceAfter = grailToken.balanceOf(account);
        uint256 xGrailTokenBalanceAfter = xGrailToken.balanceOf(account);

        rewardTokens = new address[](2);
        amountsClaimed = new uint256[](2);

        rewardTokens[0] = address(grailToken);
        amountsClaimed[0] = grailTokenBalanceAfter - grailTokenBalanceBefore;
        rewardTokens[1] = address(xGrailToken);
        amountsClaimed[1] = xGrailTokenBalanceAfter - xGrailTokenBalanceBefore;

        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);
    }

    /**
     * @notice This function is required by Camelot NFTPool if the msg.sender is a contract,
     * to confirm whether it is able to handle reward harvesting.
     * @dev This function can be wrapped in the calling contract with the same signature.
     */
    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool) {
        if (operator != address(this)) revert WrongOperator(address(this), operator);

        // prevent for harvesting to other address
        if (to != address(this)) revert WrongTo(address(this), to);

        emit OnNFTHarvest(operator, to, tokenId, grailAmount, xGrailAmount);
        return true;
    }
}
