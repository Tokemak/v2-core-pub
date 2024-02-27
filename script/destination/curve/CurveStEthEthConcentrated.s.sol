// SPDX-License-Identifier: UNLICENSED
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
 * @dev This contract creates a new Destination Vault for the Curve stETH/ETH Concentrated pool.
 * It uses the 'curve-convex' template to create the vault.
 */
contract CurveStEthEthConcentrated is CurveDestinationVaultBase {
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
            0x4352632007Ff6f3A54641D85911cCB7937064357,
            0x828b154032950C8ff7CF8085D841723Db2696056,
            0x828b154032950C8ff7CF8085D841723Db2696056,
            0xA61b57C452dadAF252D2f101f5Ba20aA86152992,
            155,
            1 // TODO double check this
        );
    }
}
