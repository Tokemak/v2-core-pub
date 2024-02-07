// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseAssetVault } from "./IBaseAssetVault.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";

interface IDestinationVault is IBaseAssetVault, IERC20 {
    enum VaultShutdownStatus {
        Active,
        Deprecated,
        Exploit
    }

    error LogicDefect();
    error UnreachableError();
    error BaseAmountReceived(uint256 amount);

    /* ******************************** */
    /* View                             */
    /* ******************************** */

    /// @notice The asset that is deposited into the vault
    function underlying() external view returns (address);

    /// @notice The asset that rewards and withdrawals to LMP is done in
    /// @inheritdoc IBaseAssetVault
    function baseAsset() external view override returns (address);

    /// @notice Debt balance of underlying asset that is in contract.  This
    ///     value includes only assets that are known as debt by the rest of the
    ///     system (i.e. transferred in on rebalance), and does not include
    ///     extraneous amounts of underlyer that may have ended up in this contract.
    function internalDebtBalance() external view returns (uint256);

    /// @notice Debt balance of underlyering asset staked externally.  This value only
    ///     includes assets known as debt to the rest of the system, and does not include
    ///     any assets staked on behalf of the DV in external contracts.
    function externalDebtBalance() external view returns (uint256);

    /// @notice Returns true value of _underlyer in DV.  Debt + tokens that may have
    ///     been transferred into the contract outside of rebalance.
    function internalQueriedBalance() external view returns (uint256);

    /// @notice Returns true value of staked _underlyer in external contract.  This
    ///     will include any _underlyer that has been staked on behalf of the DV.
    function externalQueriedBalance() external view returns (uint256);

    /// @notice Balance of underlying debt, sum of `externalDebtBalance()` and `internalDebtBalance()`.
    function balanceOfUnderlyingDebt() external view returns (uint256);

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
    /// @param incentiveCalculator_ Incentive calculator for this vault
    /// @param additionalTrackedTokens_ Additional tokens that should be considered 'tracked'
    /// @param params_ Any extra parameters needed to setup the contract
    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
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

    /// @notice Recovers any extra underlying both in DV and staked externally not tracked as debt.
    /// @dev Should be limited to TOKEN_SAVER_ROLE.
    /// @param destination The address to send excess underlyer to.
    function recoverUnderlying(address destination) external;

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

    /// @notice Estimate the base asset amount that can be withdrawn given a certain number of shares. This function
    /// performs a "simulation" of the withdrawal process. It will actually execute the withdrawal, but will then revert
    /// the transaction, returning the estimated amount in the revert reason.
    /// @param shares The number of shares to be used in the estimation.
    /// @param to The address to receive the withdrawn amount.
    /// @param account Address involved in the withdrawal; Must be set to address(0).
    /// @return The estimated base asset amount.
    function estimateWithdrawBaseAsset(uint256 shares, address to, address account) external returns (uint256);

    /// @notice Initiate the shutdown procedures for this vault
    /// @dev Should pull back tokens from staking locations
    function shutdown(VaultShutdownStatus reason) external;

    /// @notice True if the vault has been shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the reason for shutdown (or `Active` if not shutdown)
    function shutdownStatus() external view returns (VaultShutdownStatus);

    /// @notice Stats contract for this vault
    function getStats() external returns (IDexLSTStats);

    /// @notice get the marketplace rewards
    /// @return rewardTokens list of reward token addresses
    /// @return rewardRates list of reward rates
    function getMarketplaceRewards() external returns (uint256[] memory rewardTokens, uint256[] memory rewardRates);

    /// @notice Get the address of the underlying pool the vault points to
    /// @return poolAddress address of the underlying pool
    function getPool() external view returns (address poolAddress);

    /// @notice Gets the spot price of the underlying LP token
    /// @dev Price validated to be inside our tolerance against safe price. Will revert if outside.
    /// @return price Value of 1 unit of the underlying LP token in terms of the base asset
    function getValidatedSpotPrice() external returns (uint256 price);
}
