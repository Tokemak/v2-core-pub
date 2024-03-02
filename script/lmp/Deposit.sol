// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { BaseScript, console } from "script/BaseScript.sol";
import { Systems } from "script/utils/Constants.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract Deposit is BaseScript {
    // 🚨 Manually set variables below. 🚨
    address public constant VAULT_ADDRESS = 0x0491981aD3089530C7eb6e2f6c354650B35bB631;
    uint256 public constant AMOUNT = 1e18;

    function run() external {
        setUp(Systems.LST_GEN1_MAINNET);

        ILMPVault vault = ILMPVault(VAULT_ADDRESS);

        vm.startBroadcast(privateKey);

        address owner = vm.addr(privateKey);

        IWETH9 asset = IWETH9(vault.asset());

        asset.deposit{ value: AMOUNT }();

        asset.approve(address(vault), AMOUNT);

        vault.deposit(AMOUNT, owner);

        vm.stopBroadcast();
    }
}
