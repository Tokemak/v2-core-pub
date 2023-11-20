// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

library Roles {
    // --------------------------------------------------------------------
    // Central roles list used by all contracts that call AccessController
    // --------------------------------------------------------------------

    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 public constant CREATE_POOL_ROLE = keccak256("CREATE_POOL_ROLE");
    bytes32 public constant CREATE_DESTINATION_VAULT_ROLE = keccak256("CREATE_DESTINATION_VAULT_ROLE");
    bytes32 public constant REGISTRY_UPDATER = keccak256("REGISTRY_UPDATER");

    bytes32 public constant TOKEN_RECOVERY_ROLE = keccak256("TOKEN_RECOVERY_ROLE");
    bytes32 public constant DESTINATION_VAULTS_UPDATER = keccak256("DESTINATION_VAULTS_UPDATER");
    bytes32 public constant SET_WITHDRAWAL_QUEUE_ROLE = keccak256("SET_WITHDRAWAL_QUEUE_ROLE");

    bytes32 public constant DESTINATION_VAULT_OPERATOR_ROLE = keccak256("DESTINATION_VAULT_OPERATOR_ROLE");

    bytes32 public constant DV_REWARD_MANAGER_ROLE = keccak256("DV_REWARD_MANAGER_ROLE");
    bytes32 public constant LMP_REWARD_MANAGER_ROLE = keccak256("LMP_REWARD_MANAGER_ROLE");
    bytes32 public constant EXTRA_REWARD_MANAGER_ROLE = keccak256("EXTRA_REWARD_MANAGER_ROLE");

    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    bytes32 public constant CREATE_STATS_CALC_ROLE = keccak256("CREATE_STATS_CALC_ROLE");
    bytes32 public constant STATS_CALC_TEMPLATE_MGMT_ROLE = keccak256("STATS_CALC_TEMPLATE_MGMT_ROLE");
    bytes32 public constant STATS_SNAPSHOT_ROLE = keccak256("STATS_SNAPSHOT_ROLE");
    bytes32 public constant STATS_INCENTIVE_TOKEN_UPDATER = keccak256("STATS_INCENTIVE_TOKEN_UPDATER");

    bytes32 public constant SOLVER_ROLE = keccak256("SOLVER_ROLE");

    bytes32 public constant LMP_FEE_SETTER_ROLE = keccak256("LMP_FEE_SETTER_ROLE");
    bytes32 public constant LMP_MANAGEMENT_FEE_SETTER_ROLE = keccak256("LMP_MANAGEMENT_FEE_SETTER_ROLE");

    bytes32 public constant EMERGENCY_PAUSER = keccak256("EMERGENCY_PAUSER");

    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    bytes32 public constant LSD_BACKING_UPDATER = keccak256("LSD_BACKING_UPDATER");

    bytes32 public constant LMP_UPDATE_DEBT_REPORTING_ROLE = keccak256("LMP_UPDATE_DEBT_REPORTING_ROLE");
}
