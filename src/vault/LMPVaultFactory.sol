// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ILMPVaultFactory } from "src/interfaces/vault/ILMPVaultFactory.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { ILMPVault, LMPVault } from "src/vault/LMPVault.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { LMPVaultMainRewarder } from "src/rewarders/LMPVaultMainRewarder.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract LMPVaultFactory is SystemComponent, ILMPVaultFactory, SecurityBase {
    using Clones for address;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    ILMPVaultRegistry public immutable vaultRegistry;
    address public immutable template;

    mapping(bytes32 => address) public vaultTypeToPrototype;
    uint256 public defaultRewardRatio;
    uint256 public defaultRewardBlockDuration;

    modifier onlyVaultCreator() {
        if (!_hasRole(Roles.CREATE_POOL_ROLE, msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    event DefaultRewardRatioSet(uint256 rewardRatio);
    event DefaultBlockDurationSet(uint256 blockDuration);

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

    function setDefaultRewardRatio(uint256 rewardRatio) external onlyOwner {
        _setDefaultRewardRatio(rewardRatio);
    }

    function setDefaultRewardBlockDuration(uint256 blockDuration) external onlyOwner {
        _setDefaultRewardBlockDuration(blockDuration);
    }

    function createVault(
        uint256 supplyLimit,
        uint256 walletLimit,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes32 salt,
        bytes calldata extraParams
    ) external onlyVaultCreator returns (address newVaultAddress) {
        // verify params
        Errors.verifyNotZero(salt, "salt");

        address newToken = template.predictDeterministicAddress(salt);

        LMPVaultMainRewarder mainRewarder = new LMPVaultMainRewarder{ salt: salt }(
            systemRegistry,
            address(systemRegistry.toke()),
            defaultRewardRatio,
            defaultRewardBlockDuration,
            true, // allowExtraRewards
            newToken
        );

        newVaultAddress = template.cloneDeterministic(salt);

        LMPVault(newVaultAddress).initialize(supplyLimit, walletLimit, symbolSuffix, descPrefix, extraParams);
        LMPVault(newVaultAddress).setRewarder(address(mainRewarder));

        // add to VaultRegistry
        vaultRegistry.addVault(newVaultAddress);
    }

    function _setDefaultRewardRatio(uint256 rewardRatio) private {
        defaultRewardRatio = rewardRatio;

        emit DefaultRewardRatioSet(rewardRatio);
    }

    function _setDefaultRewardBlockDuration(uint256 blockDuration) private {
        defaultRewardBlockDuration = blockDuration;

        emit DefaultBlockDurationSet(blockDuration);
    }
}
