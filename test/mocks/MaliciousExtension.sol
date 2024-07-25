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

    // solhint-disable-next-line no-unused-vars
    function execute(bytes calldata) external {
        uint256 balance = IERC20(tokenToSteal).balanceOf(address(this));
        IERC20(tokenToSteal).transfer(robber, balance);
    }
}

/// @dev Designed to be delegatecall by any contract
/// @dev Will call any encoded function
contract MaliciousExtension is IDestinationVaultExtension {
    using Address for address;

    function execute(bytes calldata data) external {
        address(this).functionDelegateCall(data);
    }
}
