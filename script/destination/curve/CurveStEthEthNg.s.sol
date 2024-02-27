// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { BaseScript, console } from "script/BaseScript.sol";
import { CurveDestinationVaultBase } from "script/destination/curve/CurveDestinationVaultBase.s.sol";
import { Systems } from "script/utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";

import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";

/**
 * @dev This contract creates a new Destination Vault for the Curve stETH/ETH ng pool.
 * It uses the 'curve-convex' template to create the vault.
 */
contract CurveStEthEthNg is CurveDestinationVaultBase {

    function _getData()
        internal
        override
        pure
        returns (
            string memory template,
            address calculator,
            address curvePool,
            address curvePoolLpToken,
            address convexStaking,
            uint256 convexPoolId,
            uint256 baseAssetBurnTokenIndex
        )
    {
        return (
            "curve-convex",
            0x79CEDe27000De4Cd5c7cC270BF6d26a9425ec1BB,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x21E27a5E5513D6e65C4f830167390997aA84843a,
            0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
            177,
            1 // TODO double check this
        );
    }
}
