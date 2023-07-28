// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

// Addresses
import {
    WETH_MAINNET,
    TOKE_MAINNET,
    CURVE_META_REGISTRY_MAINNET,
    WETH_GOERLI,
    TOKE_GOERLI,
    ACCESS_CONTROLLER_MAINNET,
    ACCESS_CONTROLLER_GOERLI
} from "./utils/Addresses.sol";

/**
 * @dev Base contract for scripting.  Sets env to either Goerli or Mainnet values.  As of
 *      right now this contract sets all values regardless of whether the inheriting contract uses
 *      them or not.
 */
contract BaseScript is Script {
    ///@dev Must be set in inheriting script before `_getEnv()` is called. Default is Goerli
    bool public mainnet;

    // Set based on MAINNET flag.
    address public wethAddress;
    address public tokeAddress;
    address public curveMetaRegistryAddress;
    address public accessControllerAddress;
    uint256 public privateKey;

    function _getEnv() internal {
        if (mainnet) {
            wethAddress = WETH_MAINNET;
            tokeAddress = TOKE_MAINNET;
            curveMetaRegistryAddress = CURVE_META_REGISTRY_MAINNET;
            accessControllerAddress = ACCESS_CONTROLLER_MAINNET;
            privateKey = vm.envUint("MAINNET_PRIVATE_KEY");
        } else {
            wethAddress = WETH_GOERLI;
            tokeAddress = TOKE_GOERLI;
            accessControllerAddress = ACCESS_CONTROLLER_GOERLI;
            privateKey = vm.envUint("GOERLI_PRIVATE_KEY");
        }
    }
}
