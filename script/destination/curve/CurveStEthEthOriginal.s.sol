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
 * @dev This contract creates a new Destination Vault for the Curve stETH/ETH Original pool.
 * It uses the 'curve-convex' template to create the vault.
 */
contract CurveStEthEthOriginal is CurveDestinationVaultBase {
    function _getData()
        internal
        pure
        override
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
            0x6171F028c1D06c4ceEDf41Ae61024931281f6DaC,
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0x06325440D014e39736583c165C2963BA99fAf14E,
            0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
            25,
            1 // TODO double check this
        );
    }
}
