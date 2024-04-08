// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { TestERC20 } from "test/mocks/TestERC20.sol";

/// @title This contract is meant to be an easy implementation of weth that allows
/// both the minting / burning functionalities of TestERC20 and had the standard weth
/// deposit / withdraw functions.
contract TestWETH9 is TestERC20 {
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);

    error InvalidWithdrawalAmount();

    constructor() TestERC20("Wrapped Ether", "WETH") { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        if (balanceOf(msg.sender) < amount) revert InvalidWithdrawalAmount();
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }
}
