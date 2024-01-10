// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { IAccToke } from "src/interfaces/staking/IAccToke.sol";
import { ILMPVaultRegistry } from "./vault/ILMPVaultRegistry.sol";
import { IAccessController } from "./security/IAccessController.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ILMPVaultRouter } from "src/interfaces/vault/ILMPVaultRouter.sol";
import { ILMPVaultFactory } from "src/interfaces/vault/ILMPVaultFactory.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { IDestinationRegistry } from "./destinations/IDestinationRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { IDestinationVaultRegistry } from "./vault/IDestinationVaultRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IAsyncSwapperRegistry } from "src/interfaces/liquidation/IAsyncSwapperRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";

/// @notice Root most registry contract for the system
interface ISystemRegistry {
    /// @notice Get the TOKE contract for the system
    /// @return toke instance of TOKE used in the system
    function toke() external view returns (IERC20Metadata);

    /// @notice Get the referenced WETH contract for the system
    /// @return weth contract pointer
    function weth() external view returns (IWETH9);

    /// @notice Get the AccToke staking contract
    /// @return accToke instance of the accToke contract for the system
    function accToke() external view returns (IAccToke);

    /// @notice Get the LMP Vault registry for this system
    /// @return registry instance of the registry for this system
    function lmpVaultRegistry() external view returns (ILMPVaultRegistry registry);

    /// @notice Get the destination Vault registry for this system
    /// @return registry instance of the registry for this system
    function destinationVaultRegistry() external view returns (IDestinationVaultRegistry registry);

    /// @notice Get the access Controller for this system
    /// @return controller instance of the access controller for this system
    function accessController() external view returns (IAccessController controller);

    /// @notice Get the destination template registry for this system
    /// @return registry instance of the registry for this system
    function destinationTemplateRegistry() external view returns (IDestinationRegistry registry);

    /// @notice LMP Vault Router
    /// @return router instance of the lmp vault router
    function lmpVaultRouter() external view returns (ILMPVaultRouter router);

    /// @notice Vault factory lookup by type
    /// @return vaultFactory instance of the vault factory for this vault type
    function getLMPVaultFactoryByType(bytes32 vaultType) external view returns (ILMPVaultFactory vaultFactory);

    /// @notice Get the stats calculator registry for this system
    /// @return registry instance of the registry for this system
    function statsCalculatorRegistry() external view returns (IStatsCalculatorRegistry registry);

    /// @notice Get the root price oracle for this system
    /// @return oracle instance of the root price oracle for this system
    function rootPriceOracle() external view returns (IRootPriceOracle oracle);

    /// @notice Get the async swapper registry for this system
    /// @return registry instance of the registry for this system
    function asyncSwapperRegistry() external view returns (IAsyncSwapperRegistry registry);

    /// @notice Get the swap router for this system
    /// @return router instance of the swap router for this system
    function swapRouter() external view returns (ISwapRouter router);

    /// @notice Get the curve resolver for this system
    /// @return resolver instance of the curve resolver for this system
    function curveResolver() external view returns (ICurveResolver resolver);

    /// @notice Register given address as a Reward Token
    /// @dev Reverts if address is 0 or token was already registered
    /// @param rewardToken token address to add
    function addRewardToken(address rewardToken) external;

    /// @notice Removes given address from Reward Token list
    /// @dev Reverts if address was not registered
    /// @param rewardToken token address to remove
    function removeRewardToken(address rewardToken) external;

    /// @notice Verify if given address is registered as Reward Token
    /// @param rewardToken token address to verify
    /// @return bool that indicates true if token is registered and false if not
    function isRewardToken(address rewardToken) external view returns (bool);

    /// @notice Get the system security instance for this system
    /// @return security instance of system security for this system
    function systemSecurity() external view returns (ISystemSecurity security);

    /// @notice Get the Incentive Pricing Stats
    /// @return incentivePricing the incentive pricing contract
    function incentivePricing() external view returns (IIncentivesPricingStats);
}
