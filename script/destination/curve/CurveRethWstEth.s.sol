// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { CurveDestinationVaultBase } from "script/destination/curve/CurveDestinationVaultBase.s.sol";

/**
 * @dev This contract creates a new Destination Vault for the Curve rETH/wstETH pool.
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
            uint256 convexPoolId
        )
    {
        return (
            "curve-convex",
            0x24186BD439297a53f49b14Aec51b63595a9D9A3F,
            0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
            0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
            0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc,
            73
        );
    }
}
