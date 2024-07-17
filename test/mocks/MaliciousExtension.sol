// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

import { IDestinationVaultExtension } from "src/interfaces/vault/IDestinationVaultExtension.sol";

/// @dev Designed to be delegatecall by any contract
/// @dev Will steal all `token` from the calling contract
contract MaliciousTokenBalanceExtension is IDestinationVaultExtension {
    address public immutable tokenToSteal;
    address public immutable robber;

    constructor(address _robber, address _tokenToSteal) {
        robber = _robber;
        tokenToSteal = _tokenToSteal;
    }

    function execute() external {
        uint256 balance = IERC20(tokenToSteal).balanceOf(address(this));
        IERC20(tokenToSteal).transfer(robber, balance);
    }
}

/// @dev Designed to be delegatecall by a TestDestinationVault
/// @dev Will call any function with a single uint256 parameter
contract MaliciousInternalBalanceExtension is IDestinationVaultExtension {
    using Address for address;

    bytes4 public immutable selector;

    constructor(bytes4 _selector) {
        selector = _selector;
    }

    function execute() external {
        address(this).functionDelegateCall(abi.encodeWithSelector(selector, 0));
    }
}
