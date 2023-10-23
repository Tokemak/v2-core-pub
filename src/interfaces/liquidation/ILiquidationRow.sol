// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";

interface ILiquidationRow {
    event SwapperAdded(address indexed swapper);
    event SwapperRemoved(address indexed swapper);
    event BalanceUpdated(address indexed token, address indexed vault, uint256 balance);
    event VaultLiquidated(address indexed vault, address indexed fromToken, address indexed toToken, uint256 amount);
    event GasUsedForVault(address indexed vault, uint256 gasAmount, bytes32 action);
    event FeesTransfered(address indexed receiver, uint256 amountReceived, uint256 fees);

    error NothingToLiquidate();
    error InvalidRewardToken();
    error FeeTooHigh();
    error SellAmountMismatch(uint256 totalBalanceToLiquidate, uint256 buyAmount);
    error AmountsMismatch(uint256 sellAmount, uint256 buyAmount);

    /**
     * @notice Claim rewards from a list of vaults
     * @param vaults The list of vaults to claim rewards from
     */
    function claimsVaultRewards(IDestinationVault[] memory vaults) external;

    /**
     * @notice Add a new swapper to the whitelist
     * @param swapper The address of the swapper to be added
     */
    function addToWhitelist(address swapper) external;

    /**
     * @notice Remove a swapper from whitelist
     * @param swapper The address of the swapper to be removed
     */
    function removeFromWhitelist(address swapper) external;

    /**
     * @notice Check if a swapper is whitelisted
     * @param swapper The address of the swapper to be checked
     * @return true if the swapper is allowed
     */
    function isWhitelisted(address swapper) external view returns (bool);

    /**
     * @notice Sets the fee and the receiver of the fee.
     *  If either _feeReceiver is address(0) or _feeBps is 0, the fee feature is turned off.
     * @dev FeeBps must be less than or equal to 5_000, i.e., 50%.
     * @param _feeReceiver The address of the fee receiver. If set to address(0), the fee feature is turned off.
     * @param _feeBps The fee rate in basis points (bps). 1 bps is 0.01%. If set to 0, the fee feature is turned off.
     */
    function setFeeAndReceiver(address _feeReceiver, uint256 _feeBps) external;

    /**
     * @notice Get the balance of a specific token and vault
     * @param tokenAddress The address of the token
     * @param vaultAddress The address of the vault
     * @return The balance of the specific token and vault
     */
    function balanceOf(address tokenAddress, address vaultAddress) external view returns (uint256);

    /**
     * @notice Get the total balance of a specific token across all vaults
     * @param tokenAddress The address of the token
     * @return The total balance of the specific token across all vaults
     */
    function totalBalanceOf(address tokenAddress) external view returns (uint256);

    /**
     * @notice Get the list of reward tokens
     * @return An array containing the addresses of reward tokens
     */
    function getTokens() external view returns (address[] memory);

    /**
     * @notice Get the list of vaults associated with a specific token
     * @param tokenAddress The address of the token
     * @return An array of vault addresses associated with the given token
     */
    function getVaultsForToken(address tokenAddress) external view returns (address[] memory);

    /*
    @notice Liquidate the specified vaults' balances for a specific token
    @param fromToken The address of the token to be liquidated
    @param asyncSwapper The address of the async swapper
    @param params Swap parameters for the async swapper
    @param vaultsToLiquidate An array of vault addresses to liquidate
    */
    function liquidateVaultsForToken(
        address fromToken,
        address asyncSwapper,
        IDestinationVault[] memory vaultsToLiquidate,
        SwapParams memory params
    ) external;
}
