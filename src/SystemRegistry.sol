// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

//
//                   ▓▓
//                   ▓▓
//                   ▓▓
//                   ▓▓
//                   ▓▓
//       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓

import { Errors } from "src/utils/Errors.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { Ownable2Step } from "src/access/Ownable2Step.sol";
import { IAccToke } from "src/interfaces/staking/IAccToke.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { IAutopilotRouter } from "src/interfaces/vault/IAutopilotRouter.sol";
import { IAutopoolFactory } from "src/interfaces/vault/IAutopoolFactory.sol";
import { ISystemSecurity } from "src/interfaces/security/ISystemSecurity.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IAsyncSwapperRegistry } from "src/interfaces/liquidation/IAsyncSwapperRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";

// solhint-disable max-states-count

/// @notice Root contract of the system instance.
/// @dev All contracts in this instance of the system should be reachable from this contract
contract SystemRegistry is ISystemRegistry, Ownable2Step {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice TOKE token
    IERC20Metadata public immutable toke;

    /// @notice WETH token
    IWETH9 public immutable weth;

    /// =====================================================
    /// Private Vars
    /// =====================================================

    IAccToke private _accToke;
    IAutopoolRegistry private _autoPoolRegistry;
    IDestinationVaultRegistry private _destinationVaultRegistry;
    IAccessController private _accessController;
    IDestinationRegistry private _destinationTemplateRegistry;
    IAutopilotRouter private _autoPoolRouter;
    IRootPriceOracle private _rootPriceOracle;
    IAsyncSwapperRegistry private _asyncSwapperRegistry;
    ISwapRouter private _swapRouter;
    ICurveResolver private _curveResolver;
    IIncentivesPricingStats private _incentivePricingStats;
    ISystemSecurity private _systemSecurity;
    mapping(bytes32 => IAutopoolFactory) private _autoPoolFactoryByType;
    EnumerableSet.Bytes32Set private _autoPoolFactoryTypes;
    IStatsCalculatorRegistry private _statsCalculatorRegistry;
    EnumerableSet.AddressSet private _rewardTokens;
    IMessageProxy private _messageProxy;
    address private _receivingRouter;

    /// =====================================================
    /// Events
    /// =====================================================

    event AccTokeSet(address newAddress);
    event AutopoolRegistrySet(address newAddress);
    event DestinationVaultRegistrySet(address newAddress);
    event AccessControllerSet(address newAddress);
    event DestinationTemplateRegistrySet(address newAddress);
    event AutopilotRouterSet(address newAddress);
    event AutopoolFactorySet(bytes32 vaultType, address factoryAddress);
    event AutopoolFactoryRemoved(bytes32 vaultType, address factoryAddress);
    event StatsCalculatorRegistrySet(address newAddress);
    event RootPriceOracleSet(address rootPriceOracle);
    event AsyncSwapperRegistrySet(address newAddress);
    event SwapRouterSet(address swapRouter);
    event CurveResolverSet(address curveResolver);
    event RewardTokenAdded(address rewardToken);
    event RewardTokenRemoved(address rewardToken);
    event IncentivePricingStatsSet(address incentivePricingStats);
    event SystemSecuritySet(address security);
    event MessageProxySet(address messageProxy);
    event ReceivingRouterSet(address receivingRouter);

    /// =====================================================
    /// Errors
    /// =====================================================

    error InvalidContract(address addr);
    error DuplicateSet(address addr);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(address _toke, address _weth) {
        Errors.verifyNotZero(address(_toke), "_toke");
        Errors.verifyNotZero(address(_weth), "_weth");

        toke = IERC20Metadata(_toke);
        weth = IWETH9(_weth);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Set the AccToke for this instance of the system
    /// @param newAccToke Address of the accToke contract
    function setAccToke(address newAccToke) external onlyOwner {
        Errors.verifyNotZero(newAccToke, "newAccToke");

        if (address(_accToke) == newAccToke) {
            revert DuplicateSet(newAccToke);
        }

        _accToke = IAccToke(newAccToke);

        emit AccTokeSet(newAccToke);

        _verifySystemsAgree(address(newAccToke));
    }

    /// @notice Set the AutopoolRegistry for this instance of the system
    /// @dev Should only be able to set this value one time
    /// @param registry Address of the registry
    function setAutopoolRegistry(address registry) external onlyOwner {
        Errors.verifyNotZero(registry, "autoPoolRegistry");

        if (address(_autoPoolRegistry) != address(0)) {
            revert Errors.AlreadySet("autoPoolRegistry");
        }

        emit AutopoolRegistrySet(registry);

        _autoPoolRegistry = IAutopoolRegistry(registry);

        _verifySystemsAgree(registry);
    }

    /// @notice Set the AutopilotRouter for this instance of the system
    /// @dev allows setting multiple times
    /// @param router Address of the AutopilotRouter
    function setAutopilotRouter(address router) external onlyOwner {
        Errors.verifyNotZero(router, "autoPoolRouter");

        if (address(_autoPoolRouter) == router) {
            revert DuplicateSet(router);
        }

        emit AutopilotRouterSet(router);

        _autoPoolRouter = IAutopilotRouter(router);

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

    /// @notice Register given address as a Reward Token
    /// @dev Reverts if address is 0 or token was already registered
    /// @param rewardToken token address to add
    function addRewardToken(address rewardToken) external onlyOwner {
        Errors.verifyNotZero(rewardToken, "rewardToken");
        bool success = _rewardTokens.add(rewardToken);
        if (!success) {
            revert Errors.ItemExists();
        }
        emit RewardTokenAdded(rewardToken);
    }

    /// @notice Removes given address from Reward Token list
    /// @dev Reverts if address was not registered
    /// @param rewardToken token address to remove
    function removeRewardToken(address rewardToken) external onlyOwner {
        Errors.verifyNotZero(rewardToken, "rewardToken");
        bool success = _rewardTokens.remove(rewardToken);
        if (!success) {
            revert Errors.ItemNotFound();
        }
        emit RewardTokenRemoved(rewardToken);
    }

    /// @notice Configure an Autopool factory for type
    /// @param vaultType Type of Autopool to configure
    function setAutopoolFactory(bytes32 vaultType, address factoryAddress) external onlyOwner {
        Errors.verifyNotZero(factoryAddress, "factoryAddress");
        Errors.verifyNotZero(vaultType, "vaultType");

        // We don't care if the type already exists in the list
        // slither-disable-next-line unused-return
        _autoPoolFactoryTypes.add(vaultType);

        _autoPoolFactoryByType[vaultType] = IAutopoolFactory(factoryAddress);

        emit AutopoolFactorySet(vaultType, factoryAddress);

        _verifySystemsAgree(factoryAddress);
    }

    /// @notice Remove a previously configured Autopool factory
    /// @param vaultType Autopool type to remove the factory for
    function removeAutopoolFactory(bytes32 vaultType) external onlyOwner {
        Errors.verifyNotZero(vaultType, "vaultType");
        address factoryAddress = address(_autoPoolFactoryByType[vaultType]);

        // if returned false when trying to remove, means item wasn't in the list
        if (!_autoPoolFactoryTypes.remove(vaultType)) {
            revert Errors.ItemNotFound();
        }

        delete _autoPoolFactoryByType[vaultType];

        emit AutopoolFactoryRemoved(vaultType, factoryAddress);
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

    /// @notice Set Message Proxy instance for this system
    /// @dev Value can be replaced
    /// @param proxy Address of the Message Proxy
    function setMessageProxy(address proxy) external onlyOwner {
        Errors.verifyNotZero(proxy, "messageProxy");

        if (proxy == address(_messageProxy)) {
            revert DuplicateSet(proxy);
        }

        emit MessageProxySet(proxy);

        _messageProxy = IMessageProxy(proxy);

        _verifySystemsAgree(proxy);
    }

    /// @notice Set Receiving Router instance for this system
    /// @dev Value can be replaced
    /// @dev This is expected to be the zero address on a chain that is not receving messages from other chains
    /// @param router Address of the Receiving Router
    function setReceivingRouter(address router) external onlyOwner {
        Errors.verifyNotZero(router, "receivingRouter");

        if (router == _receivingRouter) {
            revert DuplicateSet(router);
        }

        emit ReceivingRouterSet(router);

        _receivingRouter = router;

        _verifySystemsAgree(router);
    }

    /// @inheritdoc ISystemRegistry
    function accToke() external view returns (IAccToke) {
        return _accToke;
    }

    /// @inheritdoc ISystemRegistry
    function autoPoolRegistry() external view returns (IAutopoolRegistry) {
        return _autoPoolRegistry;
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
    function autoPoolRouter() external view returns (IAutopilotRouter router) {
        return _autoPoolRouter;
    }

    /// @inheritdoc ISystemRegistry
    function getAutopoolFactoryByType(bytes32 vaultType) external view returns (IAutopoolFactory vaultFactory) {
        if (!_autoPoolFactoryTypes.contains(vaultType)) {
            revert Errors.ItemNotFound();
        }

        return _autoPoolFactoryByType[vaultType];
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

    /// @inheritdoc ISystemRegistry
    function isRewardToken(address rewardToken) external view returns (bool) {
        return _rewardTokens.contains(rewardToken);
    }

    /// @inheritdoc ISystemRegistry
    function messageProxy() external view returns (IMessageProxy) {
        return _messageProxy;
    }

    /// @inheritdoc ISystemRegistry
    function receivingRouter() external view returns (address) {
        return _receivingRouter;
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    /// @notice Verifies that a system bound contract matches this contract
    /// @dev All system bound contracts must match a registry contract. Will revert on mismatch
    /// @param dep The contract to check
    function _verifySystemsAgree(address dep) private view {
        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) =
            dep.staticcall(abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector));
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
