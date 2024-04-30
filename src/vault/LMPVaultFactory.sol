// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry, IWETH9 } from "src/interfaces/ISystemRegistry.sol";
import { ILMPVaultFactory } from "src/interfaces/vault/ILMPVaultFactory.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { LMPVaultMainRewarder } from "src/rewarders/LMPVaultMainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { Roles } from "src/libs/Roles.sol";

contract LMPVaultFactory is SystemComponent, ILMPVaultFactory, SecurityBase {
    using Clones for address;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice Strategy templates that can be used with this vault template
    /// @dev Exposed via `getStrategyTemplates() and isStrategyTemplate()`
    EnumerableSet.AddressSet internal _strategyTemplates;

    ILMPVaultRegistry public immutable vaultRegistry;

    address public immutable template;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    mapping(bytes32 => address) public vaultTypeToPrototype;

    uint256 public defaultRewardRatio;

    uint256 public defaultRewardBlockDuration;

    /// =====================================================
    /// Modifiers
    /// =====================================================

    modifier onlyVaultCreator() {
        if (!_hasRole(Roles.LMP_VAULT_FACTORY_VAULT_CREATOR, msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    /// =====================================================
    /// Events
    /// =====================================================

    event DefaultRewardRatioSet(uint256 rewardRatio);
    event DefaultBlockDurationSet(uint256 blockDuration);
    event StrategyTemplateAdded(address template);
    event StrategyTemplateRemoved(address template);

    /// =====================================================
    /// Errors
    /// =====================================================

    error InvalidStrategy();
    error InvalidEthAmount(uint256 amount);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry,
        address _template,
        uint256 _defaultRewardRatio,
        uint256 _defaultRewardBlockDuration
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(_template, "template");

        // slither-disable-next-line missing-zero-check
        template = _template;
        vaultRegistry = systemRegistry.lmpVaultRegistry();

        // Zero is valid here
        _setDefaultRewardRatio(_defaultRewardRatio);
        _setDefaultRewardBlockDuration(_defaultRewardBlockDuration);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function addStrategyTemplate(address strategyTemplate) external hasRole(Roles.LMP_VAULT_FACTORY_MANAGER) {
        if (!_strategyTemplates.add(strategyTemplate)) {
            revert Errors.ItemExists();
        }

        emit StrategyTemplateAdded(strategyTemplate);
    }

    function removeStrategyTemplate(address strategyTemplate) external hasRole(Roles.LMP_VAULT_FACTORY_MANAGER) {
        if (!_strategyTemplates.remove(strategyTemplate)) {
            revert Errors.ItemNotFound();
        }

        emit StrategyTemplateRemoved(strategyTemplate);
    }

    function setDefaultRewardRatio(uint256 rewardRatio) external hasRole(Roles.LMP_VAULT_FACTORY_MANAGER) {
        _setDefaultRewardRatio(rewardRatio);
    }

    function setDefaultRewardBlockDuration(uint256 blockDuration) external hasRole(Roles.LMP_VAULT_FACTORY_MANAGER) {
        _setDefaultRewardBlockDuration(blockDuration);
    }

    function createVault(
        address strategyTemplate,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes32 salt,
        bytes calldata extraParams
    ) external payable onlyVaultCreator returns (address newVaultAddress) {
        // verify params
        Errors.verifyNotZero(salt, "salt");

        if (!_strategyTemplates.contains(strategyTemplate)) {
            revert InvalidStrategy();
        }

        address newToken = template.predictDeterministicAddress(salt);
        address newStrategy = strategyTemplate.predictDeterministicAddress(salt);

        LMPVaultMainRewarder mainRewarder = new LMPVaultMainRewarder{ salt: salt }(
            systemRegistry,
            address(systemRegistry.toke()),
            defaultRewardRatio,
            defaultRewardBlockDuration,
            true, // allowExtraRewards
            newToken
        );

        newVaultAddress = template.cloneDeterministic(salt);

        // For Autopool deposit on initialization.
        uint256 wethInitAmount = LMPVault(newVaultAddress).WETH_INIT_DEPOSIT();
        IWETH9 weth = systemRegistry.weth();
        if (msg.value != wethInitAmount) revert InvalidEthAmount(msg.value);
        weth.deposit{ value: wethInitAmount }();
        LibAdapter._approve(weth, newVaultAddress, wethInitAmount);

        LMPVault(newVaultAddress).initialize(newStrategy, symbolSuffix, descPrefix, extraParams);
        LMPVault(newVaultAddress).setRewarder(address(mainRewarder));
        LMPStrategy(strategyTemplate.cloneDeterministic(salt)).initialize(newVaultAddress);

        // add to VaultRegistry
        vaultRegistry.addVault(newVaultAddress);
    }

    function getStrategyTemplates() public view returns (address[] memory) {
        return _strategyTemplates.values();
    }

    function isStrategyTemplate(address addr) public view returns (bool) {
        return _strategyTemplates.contains(addr);
    }

    /// =====================================================
    /// Functions - Private
    /// =====================================================

    function _setDefaultRewardRatio(uint256 rewardRatio) private {
        defaultRewardRatio = rewardRatio;

        emit DefaultRewardRatioSet(rewardRatio);
    }

    function _setDefaultRewardBlockDuration(uint256 blockDuration) private {
        defaultRewardBlockDuration = blockDuration;

        emit DefaultBlockDurationSet(blockDuration);
    }
}
