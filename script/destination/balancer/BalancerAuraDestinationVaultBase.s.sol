// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,reason-string,gas-custom-errors

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";

import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";

abstract contract BalancerAuraDestinationVaultBase is BaseScript {
    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        vm.startBroadcast(privateKey);

        if (address(destinationVaultFactory) == address(0)) {
            revert("Destination Vault Factory not set");
        }

        (string memory template, address calculator, BalancerAuraDestinationVault.InitParams memory initParams) =
            _getData();
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            destinationVaultFactory.create(
                template,
                constants.tokens.weth,
                initParams.balancerPool,
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
        returns (string memory template, address calculator, BalancerAuraDestinationVault.InitParams memory initParams);
}
