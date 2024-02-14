// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { CryticERC4626PropertyTests } from "crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
import { TestERC20Token } from "crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { BasePoolSetup } from "test/echidna/fuzz/vault/BaseSetup.sol";

contract CryticERC4626Harness is CryticERC4626PropertyTests, BasePoolSetup {
    constructor() {
        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        initializeBaseSetup(address(_asset));

        _pool.initialize(type(uint112).max, type(uint112).max, address(_strategy), "SYMBOL", "NAME", abi.encode(""));
        _pool.setDisableNavDecreaseCheck(true);
        _pool.setCryticFnsEnabled(true);

        initialize(address(_pool), address(_asset), true);
    }
}
