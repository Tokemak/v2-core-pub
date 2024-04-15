// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { CurveDestinationVaultBase } from "script/destination/curve/CurveDestinationVaultBase.s.sol";

/**
 * @dev This contract creates a new Destination Vault for the Curve Curve cbETH/ETH pool.
 * It uses the 'curve-convex' template to create the vault.
 */
contract CurveRethWstEth is CurveDestinationVaultBase {
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
            0x1406311f198A72CcA5F895141238E6043e4984B6,
            0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A,
            0x5b6C539b224014A09B3388e51CaAA8e354c959C8,
            0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699,
            127,
            1 // TODO double check this
        );
    }
}
