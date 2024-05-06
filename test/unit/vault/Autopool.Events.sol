// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { IAutopool } from "src/interfaces/vault/IAutopool.sol";

library Events {
    event Shutdown(IAutopool.VaultShutdownStatus reason);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    // solhint-disable-next-line
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event Transfer(address indexed sender, address indexed receiver, uint256 amount);
}
