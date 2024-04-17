// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { CurveDestinationVaultBase } from "script/destination/curve/CurveDestinationVaultBase.s.sol";

/**
 * @dev This contract creates a new Destination Vault for the Curve stETH/ETH ng pool.
 * It uses the 'curve-convex' template to create the vault.
 */
contract CurveOsEthReth is CurveDestinationVaultBase {
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
            uint256 convexPoolId
        )
    {
        return (
            "curve-convex",
            address(0),
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
            0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e,
            268
        );
    }
}
