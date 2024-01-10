// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

// solhint-disable max-states-count

import { Errors } from "src/utils/Errors.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { Ownable2Step } from "./access/Ownable2Step.sol";
import { IAccToke } from "src/interfaces/staking/IAccToke.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ILMPVaultRouter } from "src/interfaces/vault/ILMPVaultRouter.sol";
import { ILMPVaultFactory } from "src/interfaces/vault/ILMPVaultFactory.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IAsyncSwapperRegistry } from "src/interfaces/liquidation/IAsyncSwapperRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Root contract of the system instance.
/// @dev All contracts in this instance of the system should be reachable from this contract
contract SystemRegistry is ISystemRegistry, Ownable2Step {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    IERC20Metadata public immutable toke;
    IWETH9 public immutable weth;
    IAccToke private _accToke;
    ILMPVaultRegistry private _lmpVaultRegistry;
    IDestinationVaultRegistry private _destinationVaultRegistry;
    IAccessController private _accessController;
    IDestinationRegistry private _destinationTemplateRegistry;
    ILMPVaultRouter private _lmpVaultRouter;
    IRootPriceOracle private _rootPriceOracle;
    IAsyncSwapperRegistry private _asyncSwapperRegistry;
    ISwapRouter private _swapRouter;
    ICurveResolver private _curveResolver;
    IIncentivesPricingStats private _incentivePricingStats;
    ISystemSecurity private _systemSecurity;

    mapping(bytes32 => ILMPVaultFactory) private _lmpVaultFactoryByType;
    EnumerableSet.Bytes32Set private _lmpVaultFactoryTypes;
    IStatsCalculatorRegistry private _statsCalculatorRegistry;
    EnumerableSet.AddressSet private _rewardTokens;

    /* ******************************** */
    /* Events                           */
    /* ******************************** */

    event AccTokeSet(address newAddress);
    event LMPVaultRegistrySet(address newAddress);
    event DestinationVaultRegistrySet(address newAddress);
    event AccessControllerSet(address newAddress);
    event DestinationTemplateRegistrySet(address newAddress);
    event LMPVaultRouterSet(address newAddress);
    event LMPVaultFactorySet(bytes32 vaultType, address factoryAddress);
    event LMPVaultFactoryRemoved(bytes32 vaultType, address factoryAddress);
    event StatsCalculatorRegistrySet(address newAddress);
    event RootPriceOracleSet(address rootPriceOracle);
    event AsyncSwapperRegistrySet(address newAddress);
    event SwapRouterSet(address swapRouter);
    event CurveResolverSet(address curveResolver);
    event RewardTokenAdded(address rewardToken);
    event RewardTokenRemoved(address rewardToken);
    event IncentivePricingStatsSet(address incentivePricingStats);
    event SystemSecuritySet(address security);

    /* ******************************** */
    /* Errors                           */
    /* ******************************** */

    error InvalidContract(address addr);
    error DuplicateSet(address addr);

    /* ******************************** */
    /* Constructor                           */
    /* ******************************** */

    constructor(address _toke, address _weth) {
        Errors.verifyNotZero(address(_toke), "_toke");
        Errors.verifyNotZero(address(_weth), "_weth");

        toke = IERC20Metadata(_toke);
        weth = IWETH9(_weth);
    }

    /* ******************************** */
    /* Views                            */
    /* ******************************** */

    /// @inheritdoc ISystemRegistry
    function accToke() external view returns (IAccToke) {
        return _accToke;
    }

    /// @inheritdoc ISystemRegistry
    function lmpVaultRegistry() external view returns (ILMPVaultRegistry) {
        return _lmpVaultRegistry;
    }

    /// @inheritdoc ISystemRegistry
    function destinationVaultRegistry() external view returns (IDestinationVaultRegistry) {
        return _destinationVaultRegistry;
    }

    /// @inheritdoc ISystemRegistry
    function accessController() external view returns (IAccessController) {
        return _accessController;
    }

    /// @inheritdoc ISystemRegistry
    function destinationTemplateRegistry() external view returns (IDestinationRegistry) {
        return _destinationTemplateRegistry;
    }

    /// @inheritdoc ISystemRegistry
    function lmpVaultRouter() external view returns (ILMPVaultRouter router) {
        return _lmpVaultRouter;
    }

    /// @inheritdoc ISystemRegistry
    function getLMPVaultFactoryByType(bytes32 vaultType) external view returns (ILMPVaultFactory vaultFactory) {
        if (!_lmpVaultFactoryTypes.contains(vaultType)) {
            revert Errors.ItemNotFound();
        }

        return _lmpVaultFactoryByType[vaultType];
    }

    /// @inheritdoc ISystemRegistry
    function statsCalculatorRegistry() external view returns (IStatsCalculatorRegistry) {
        return _statsCalculatorRegistry;
    }

    /// @inheritdoc ISystemRegistry
    function rootPriceOracle() external view returns (IRootPriceOracle) {
        return _rootPriceOracle;
    }

    /// @inheritdoc ISystemRegistry
    function asyncSwapperRegistry() external view returns (IAsyncSwapperRegistry) {
        return _asyncSwapperRegistry;
    }

    /// @inheritdoc ISystemRegistry
    function swapRouter() external view returns (ISwapRouter) {
        return _swapRouter;
    }

    /// @inheritdoc ISystemRegistry
    function curveResolver() external view returns (ICurveResolver) {
        return _curveResolver;
    }

    /// @inheritdoc ISystemRegistry
    function systemSecurity() external view returns (ISystemSecurity) {
        return _systemSecurity;
    }

    /// @inheritdoc ISystemRegistry
    function incentivePricing() external view returns (IIncentivesPricingStats) {
        return _incentivePricingStats;
    }

    /* ******************************** */
    /* Function                         */
    /* ******************************** */

    /// @notice Set the AccToke for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param newAccToke Address of the accToke contract
    function setAccToke(address newAccToke) external onlyOwner {
        Errors.verifyNotZero(newAccToke, "newAccToke");

        if (address(_accToke) != address(0)) {
            revert Errors.AlreadySet("accToke");
        }

        _accToke = IAccToke(newAccToke);

        emit AccTokeSet(newAccToke);

        _verifySystemsAgree(address(newAccToke));
    }

    /// @notice Set the LMP Vault Registry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setLMPVaultRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "lmpVaultRegistry");

        if (address(_lmpVaultRegistry) != address(0)) {
            revert Errors.AlreadySet("lmpVaultRegistry");
        }

        emit LMPVaultRegistrySet(registry);

        _lmpVaultRegistry = ILMPVaultRegistry(registry);

        _verifySystemsAgree(registry);
    }

    /// @notice Set the LMP Vault Router for this instance of the system
    /// @dev allows setting multiple times
    /// @param router Address of the LMP Vault Router
    function setLMPVaultRouter(address router) external onlyOwner {
        Errors.verifyNotZero(router, "lmpVaultRouter");

        if (address(_lmpVaultRouter) == router) {
            revert DuplicateSet(router);
        }

        emit LMPVaultRouterSet(router);

        _lmpVaultRouter = ILMPVaultRouter(router);

        _verifySystemsAgree(router);
    }

    /// @notice Set the Destination Vault Registry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setDestinationVaultRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "destinationVaultRegistry");

        if (address(_destinationVaultRegistry) != address(0)) {
            revert Errors.AlreadySet("destinationVaultRegistry");
        }

        emit DestinationVaultRegistrySet(registry);

        _destinationVaultRegistry = IDestinationVaultRegistry(registry);

        _verifySystemsAgree(registry);
    }

    /// @notice Set the Access Controller for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param controller Address of the access controller
    function setAccessController(address controller) external onlyOwner {
        Errors.verifyNotZero(controller, "accessController");

        if (address(_accessController) != address(0)) {
            revert Errors.AlreadySet("accessController");
        }

        emit AccessControllerSet(controller);

        _accessController = IAccessController(controller);

        _verifySystemsAgree(controller);
    }

    /// @notice Set the Destination Template Registry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setDestinationTemplateRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "destinationTemplateRegistry");

        if (address(_destinationTemplateRegistry) != address(0)) {
            revert Errors.AlreadySet("destinationTemplateRegistry");
        }

        emit DestinationTemplateRegistrySet(registry);

        _destinationTemplateRegistry = IDestinationRegistry(registry);

        _verifySystemsAgree(registry);
    }

    /// @notice Set the Stats Calculator Registry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setStatsCalculatorRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "statsCalculatorRegistry");

        if (address(_statsCalculatorRegistry) != address(0)) {
            revert Errors.AlreadySet("statsCalculatorRegistry");
        }

        emit StatsCalculatorRegistrySet(registry);

        _statsCalculatorRegistry = IStatsCalculatorRegistry(registry);

        _verifySystemsAgree(registry);
    }

    /// @notice Set the Root Price Oracle for this instance of the system
    /// @dev This value can be set multiple times, but never back to 0
    /// @param oracle Address of the oracle
    function setRootPriceOracle(address oracle) external onlyOwner {
        Errors.verifyNotZero(oracle, "oracle");

        if (oracle == address(_rootPriceOracle)) {
            revert DuplicateSet(oracle);
        }

        emit RootPriceOracleSet(oracle);

        _rootPriceOracle = IRootPriceOracle(oracle);

        _verifySystemsAgree(oracle);
    }

    /// @notice Set the Incentive Pricing Stats for this instance of the system
    /// @dev This value can be set multiple times, but never back to 0
    /// @param incentivePricingStats Address of the IIncentivePricingStats
    function setIncentivePricingStats(address incentivePricingStats) external onlyOwner {
        Errors.verifyNotZero(incentivePricingStats, "incentivePricingStats");

        if (incentivePricingStats == address(_incentivePricingStats)) {
            revert DuplicateSet(incentivePricingStats);
        }

        emit IncentivePricingStatsSet(incentivePricingStats);

        _incentivePricingStats = IIncentivesPricingStats(incentivePricingStats);

        _verifySystemsAgree(incentivePricingStats);
    }

    /// @notice Set the Async Swapper Registry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setAsyncSwapperRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "asyncSwapperRegistry");

        if (address(_asyncSwapperRegistry) != address(0)) {
            revert Errors.AlreadySet("asyncSwapperRegistry");
        }

        emit AsyncSwapperRegistrySet(registry);

        _asyncSwapperRegistry = IAsyncSwapperRegistry(registry);

        _verifySystemsAgree(address(_asyncSwapperRegistry));
    }

    /// @notice Set the Swap Router for this instance of the system
    /// @dev This value can be set multiple times, but never back to 0
    /// @param router Address of the router
    function setSwapRouter(address router) external onlyOwner {
        Errors.verifyNotZero(router, "router");

        if (router == address(_swapRouter)) {
            revert DuplicateSet(router);
        }

        emit SwapRouterSet(router);

        _swapRouter = ISwapRouter(router);

        _verifySystemsAgree(router);
    }

    /// @notice Set the Curve Resolver for this instance of the system
    /// @dev This value can be set multiple times, but never back to 0
    /// @param resolver Address of the resolver
    function setCurveResolver(address resolver) external onlyOwner {
        Errors.verifyNotZero(resolver, "resolver");

        if (resolver == address(_curveResolver)) {
            revert DuplicateSet(resolver);
        }

        emit CurveResolverSet(resolver);

        _curveResolver = ICurveResolver(resolver);

        // Has no other dependencies in the system so no call
        // to verifySystemsAgree
    }

    /// @inheritdoc ISystemRegistry
    function addRewardToken(address rewardToken) external onlyOwner {
        Errors.verifyNotZero(rewardToken, "rewardToken");
        bool success = _rewardTokens.add(rewardToken);
        if (!success) {
            revert Errors.ItemExists();
        }
        emit RewardTokenAdded(rewardToken);
    }

    /// @inheritdoc ISystemRegistry
    function removeRewardToken(address rewardToken) external onlyOwner {
        Errors.verifyNotZero(rewardToken, "rewardToken");
        bool success = _rewardTokens.remove(rewardToken);
        if (!success) {
            revert Errors.ItemNotFound();
        }
        emit RewardTokenRemoved(rewardToken);
    }

    /// @inheritdoc ISystemRegistry
    function isRewardToken(address rewardToken) external view returns (bool) {
        return _rewardTokens.contains(rewardToken);
    }

    /* ******************************** */
    /* LMP Vault Factories              */
    /* ******************************** */
    function setLMPVaultFactory(bytes32 vaultType, address factoryAddress) external onlyOwner {
        Errors.verifyNotZero(factoryAddress, "factoryAddress");
        Errors.verifyNotZero(vaultType, "vaultType");

        // set the factory (note: slither exception due to us hard setting it regardless / no diff use case)
        // slither-disable-next-line unused-return
        _lmpVaultFactoryTypes.add(vaultType);

        _lmpVaultFactoryByType[vaultType] = ILMPVaultFactory(factoryAddress);

        emit LMPVaultFactorySet(vaultType, factoryAddress);

        _verifySystemsAgree(factoryAddress);
    }

    function removeLMPVaultFactory(bytes32 vaultType) external onlyOwner {
        Errors.verifyNotZero(vaultType, "vaultType");
        address factoryAddress = address(_lmpVaultFactoryByType[vaultType]);

        // if returned false when trying to remove, means item wasn't in the list
        if (!_lmpVaultFactoryTypes.remove(vaultType)) {
            revert Errors.ItemNotFound();
        }

        delete _lmpVaultFactoryByType[vaultType];

        emit LMPVaultFactoryRemoved(vaultType, factoryAddress);
    }

    /// @notice Set the System Security instance for this system
    /// @dev Should only be able to set this value one time
    /// @param security Address of the security contract
    function setSystemSecurity(address security) external onlyOwner {
        Errors.verifyNotZero(security, "security");

        if (address(_systemSecurity) != address(0)) {
            revert Errors.AlreadySet("security");
        }

        emit SystemSecuritySet(security);

        _systemSecurity = ISystemSecurity(security);

        _verifySystemsAgree(security);
    }

    /// @notice Verifies that a system bound contract matches this contract
    /// @dev All system bound contracts must match a registry contract. Will revert on mismatch
    /// @param dep The contract to check
    function _verifySystemsAgree(address dep) internal view {
        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = dep.staticcall(abi.encodeWithSignature("getSystemRegistry()"));
        // slither-disable-end low-level-calls
        if (success && data.length > 0) {
            address depRegistry = abi.decode(data, (address));
            if (depRegistry != address(this)) {
                revert Errors.SystemMismatch(address(this), depRegistry);
            }
        } else {
            revert InvalidContract(dep);
        }
    }
}
