// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";

interface ILMPVault is IERC4626, IERC20Permit {
    enum VaultShutdownStatus {
        Active,
        Deprecated,
        Exploit
    }

    /* ******************************** */
    /*      Events                      */
    /* ******************************** */
    event TokensPulled(address[] tokens, uint256[] amounts, address[] destinations);
    event TokensRecovered(address[] tokens, uint256[] amounts, address[] destinations);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event RewarderSet(address newRewarder, address oldRewarder);
    event DestinationDebtReporting(address destination, uint256 debtValue, uint256 claimed, uint256 claimGasUsed);
    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 idle, uint256 debt);
    event ManagementFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Shutdown(VaultShutdownStatus reason);

    /* ******************************** */
    /*      Errors                      */
    /* ******************************** */

    error ERC4626MintExceedsMax(uint256 shares, uint256 maxMint);
    error ERC4626DepositExceedsMax(uint256 assets, uint256 maxDeposit);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
    error AmountExceedsAllowance(uint256 shares, uint256 allowed);
    error InvalidShutdownStatus(VaultShutdownStatus status);

    error WithdrawalFailed();
    error DepositFailed();
    error InsufficientFundsInDestinations(uint256 deficit);
    error WithdrawalIncomplete();

    /// @notice Query the type of vault
    function vaultType() external view returns (bytes32);

    /// @notice Allow token recoverer to collect dust / unintended transfers (non-tracked assets only)
    function recover(address[] calldata tokens, uint256[] calldata amounts, address[] calldata destinations) external;

    /// @notice Set the order of destination vaults used for withdrawals
    // NOTE: will be done going directly to strategy (IStrategy) vault points to.
    //       How it'll delegate is still being decided
    // function setWithdrawalQueue(address[] calldata destinations) external;

    /// @notice Set the withdrawal queue to be used when taking out Assets
    /// @param _destinations The ordered list of destination vaults to go for withdrawals
    function setWithdrawalQueue(address[] calldata _destinations) external;

    /// @notice Get the withdrawal queue to be used when taking out Assets
    function getWithdrawalQueue() external returns (IDestinationVault[] memory _destinations);

    /// @notice Get a list of destination vaults with pending assets to clear out
    function getRemovalQueue() external view returns (address[] memory);

    /// @notice Remove emptied destination vault from pending removal queue
    function removeFromRemovalQueue(address vaultToRemove) external;

    /// @notice Initiate the shutdown procedures for this vault
    function shutdown(VaultShutdownStatus reason) external;

    /// @notice True if the vault has been shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the reason for shutdown (or `Active` if not shutdown)
    function shutdownStatus() external view returns (VaultShutdownStatus);

    /// @notice gets the list of supported destination vaults for the LMP/Strategy
    /// @return _destinations List of supported destination vaults
    function getDestinations() external view returns (address[] memory _destinations);

    /// @notice Current performance fee taken on profit. 100% == 10000
    function performanceFeeBps() external view returns (uint256);

    /// @notice The amount of baseAsset deposited into the contract pending deployment
    function totalIdle() external view returns (uint256);

    /// @notice The current (though cached) value of assets we've deployed
    function totalDebt() external view returns (uint256);

    /// @notice get a destinations last reported debt value
    /// @param destVault the address of the target destination
    /// @return destinations last reported debt value
    function getDestinationInfo(address destVault) external view returns (LMPDebt.DestinationInfo memory);

    /// @notice check if a destination is registered with the vault
    function isDestinationRegistered(address destination) external view returns (bool);

    /// @notice get if a destinationVault is queued for removal by the LMPVault
    function isDestinationQueuedForRemoval(address destination) external view returns (bool);

    /// @notice add (or move to if it already exists) a destination to the head of the withdrawal queue
    function addToWithdrawalQueueHead(address destinationVault) external;

    /// @notice add (or move to if it already exists) a destination to the tail of the withdrawal queue
    function addToWithdrawalQueueTail(address destinationVault) external;

    /// @notice Returns instance of vault rewarder.
    function rewarder() external view returns (IMainRewarder);

    /// @notice Returns all past rewarders.
    function getPastRewarders() external view returns (address[] memory _pastRewarders);

    /// @notice Returns boolean telling whether address passed in is past rewarder.
    function isPastRewarder(address _pastRewarder) external view returns (bool);
}
