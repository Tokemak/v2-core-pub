// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string

import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";

import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";

abstract contract CurveDestinationVaultBase is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        if (address(destinationVaultFactory) == address(0)) {
            revert("Destination Vault Factory not set");
        }

        (
            string memory template,
            address calculator,
            address curvePool,
            address curvePoolLpToken,
            address convexStaking,
            uint256 convexPoolId,
            uint256 baseAssetBurnTokenIndex
        ) = _getData();

        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: curvePool,
            convexStaking: convexStaking,
            convexPoolId: convexPoolId,
            baseAssetBurnTokenIndex: baseAssetBurnTokenIndex
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            destinationVaultFactory.create(
                template,
                constants.tokens.weth,
                curvePoolLpToken,
                calculator,
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number)),
                initParamBytes
            )
        );

        console.log("New vault: %s", newVault);

        vm.stopBroadcast();
    }

    function _getData()
        internal
        virtual
        returns (
            string memory template,
            address calculator,
            address curvePool,
            address curvePoolLpToken,
            address convexStaking,
            uint256 convexPoolId,
            uint256 baseAssetBurnTokenIndex
        );
}
