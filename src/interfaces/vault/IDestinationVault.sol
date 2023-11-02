// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseAssetVault } from "./IBaseAssetVault.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IDestinationVault is IBaseAssetVault, IERC20 {
    enum VaultShutdownStatus {
        Active,
        Deprecated,
        Exploit
    }

    /* ******************************** */
    /* View                             */
    /* ******************************** */

    /// @notice The asset that is deposited into the vault
    function underlying() external view returns (address);

    /// @notice The asset that rewards and withdrawals to LMP is done in
    /// @inheritdoc IBaseAssetVault
    function baseAsset() external view override returns (address);

    /// @notice Balance of underlying asset that resides in the contract
    function internalBalance() external view returns (uint256);

    /// @notice Balance of underlying asset that has been staked externally
    function externalBalance() external view returns (uint256);

    /// @notice Balance of underlying asset wherever it may be staked
    function balanceOfUnderlying() external view returns (uint256);

    /// @notice Rewarder for this vault
    function rewarder() external view returns (address);

    /// @notice Exchange this destination vault points to
    function exchangeName() external view returns (string memory);

    /// @notice Tokens that base asset can be swapped into
    function underlyingTokens() external view returns (address[] memory);

    /* ******************************** */
    /* Events                           */
    /* ******************************** */

    event Donated(address sender, uint256 amount);
    event Withdraw(
        uint256 target, uint256 actual, uint256 debtLoss, uint256 claimLoss, uint256 fromIdle, uint256 fromDebt
    );

    /* ******************************** */
    /* Errors                           */
    /* ******************************** */

    error ZeroAddress(string paramName);
    error InvalidShutdownStatus(VaultShutdownStatus status);

    /* ******************************** */
    /* Functions                        */
    /* ******************************** */

    /// @notice Setup the contract. These will be cloned so no constructor
    /// @param baseAsset_ Base asset of the system. WETH/USDC/etc
    /// @param underlyer_ Underlying asset the vault will wrap
    /// @param rewarder_ Reward tracker for this vault
    /// @param additionalTrackedTokens_ Additional tokens that should be considered 'tracked'
    /// @param params_ Any extra parameters needed to setup the contract
    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) external;

    /// @notice Calculates the current value of our debt
    /// @dev Queries the current value of all tokens we have deployed, whether its a single place, multiple, staked, etc
    /// @return value The current value of our debt in terms of the baseAsset
    function debtValue() external returns (uint256 value);

    /// @notice Calculates the current value of a portion of the debt based on shares
    /// @dev Queries the current value of all tokens we have deployed, whether its a single place, multiple, staked, etc
    /// @param shares The number of shares to value
    /// @return value The current value of our debt in terms of the baseAsset
    function debtValue(uint256 shares) external returns (uint256 value);

    /// @notice Collects any earned rewards from staking, incentives, etc. Transfers to sender
    /// @dev Should be limited to LIQUIDATOR_ROLE. Rewards must be collected before claimed
    /// @return amounts amount of rewards claimed for each token
    /// @return tokens tokens claimed
    function collectRewards() external returns (uint256[] memory amounts, address[] memory tokens);

    /// @notice Pull any non-tracked token to the specified destination
    /// @dev Should be limited to TOKEN_RECOVERY_ROLE
    function recover(address[] calldata tokens, uint256[] calldata amounts, address[] calldata destinations) external;

    /// @notice Deposit underlying to receive destination vault shares
    /// @param amount amount of base lp asset to deposit
    function depositUnderlying(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraw underlying by burning destination vault shares
    /// @param shares amount of destination vault shares to burn
    /// @param to destination of the underlying asset
    /// @return amount underlyer amount 'to' received
    function withdrawUnderlying(uint256 shares, address to) external returns (uint256 amount);

    /// @notice Burn specified shares for underlyer swapped to base asset
    /// @param shares amount of vault shares to burn
    /// @param to destination of the base asset
    /// @return amount base asset amount 'to' received
    function withdrawBaseAsset(uint256 shares, address to) external returns (uint256 amount);

    /// @notice Initiate the shutdown procedures for this vault
    /// @dev Should pull back tokens from staking locations
    function shutdown(VaultShutdownStatus reason) external;

    /// @notice True if the vault has been shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the reason for shutdown (or `Active` if not shutdown)
    function shutdownStatus() external view returns (VaultShutdownStatus);
}
