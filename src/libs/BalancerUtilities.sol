// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";

library BalancerUtilities {
    error BalancerVaultReentrancy();

    // 400 is Balancers Vault REENTRANCY error code
    bytes32 internal constant REENTRANCY_ERROR_HASH = keccak256(abi.encodeWithSignature("Error(string)", "BAL#400"));

    /**
     * @notice Verifies reentrancy to the Balancer Vault
     * @dev Reverts if gets BAL#400 error
     */
    function checkReentrancy(address balancerVault) external view {
        // solhint-disable max-line-length
        // https://github.com/balancer/balancer-v2-monorepo/blob/90f77293fef4b8782feae68643c745c754bac45c/pkg/pool-utils/contracts/lib/VaultReentrancyLib.sol
        (, bytes memory returnData) = balancerVault.staticcall(
            abi.encodeWithSelector(IVault.manageUserBalance.selector, new IVault.UserBalanceOp[](0))
        );
        if (keccak256(returnData) == REENTRANCY_ERROR_HASH) {
            revert BalancerVaultReentrancy();
        }
    }

    /**
     * @notice Checks if a given address is Balancer Composable pool
     * @dev Using the presence of a getBptIndex() fn as an indicator of pool type
     */
    function isComposablePool(address pool) public view returns (bool) {
        // slither-disable-start low-level-calls
        // solhint-disable-next-line no-unused-vars
        (bool success, bytes memory data) = pool.staticcall(abi.encodeWithSignature("getBptIndex()"));
        if (success) {
            return data.length > 0;
        }
        // slither-disable-end low-level-calls
        return success;
    }

    /**
     * @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
     */
    function _convertERC20sToAddresses(IERC20[] memory tokens) internal pure returns (address[] memory assets) {
        //slither-disable-start assembly
        //solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
        //slither-disable-end assembly
    }

    /**
     * @dev This helper function to retrieve Balancer pool tokens
     */
    function _getPoolTokens(
        IVault balancerVault,
        address balancerPool
    ) internal view returns (IERC20[] memory assets) {
        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

        // slither-disable-next-line unused-return
        (IERC20[] memory balancerPoolTokens,,) = balancerVault.getPoolTokens(poolId);

        assets = balancerPoolTokens;
    }
}
