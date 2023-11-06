// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// NOTE: should be put back in once the fuzzing constraints can be implemented

import { ERC4626Test } from "erc4626-tests/ERC4626.test.sol";

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { ERC4626Mock, IERC20Metadata } from "openzeppelin-contracts/mocks/ERC4626Mock.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ILMPVault, LMPVault } from "src/vault/LMPVault.sol";

import { Roles } from "src/libs/Roles.sol";

contract LMPVaultTest is ERC4626Test, BaseTest {
    address private lmpStrategy = vm.addr(10_001);

    function setUp() public override(BaseTest, ERC4626Test) {
        // everything's mocked, so disable forking
        super._setUp(false);

        _underlying_ = address(baseAsset);

        // create vault
        bytes memory initData = abi.encode(LMPVault.ExtraData({ lmpStrategyAddress: lmpStrategy }));
        LMPVault vault = LMPVault(
            lmpVaultFactory.createVault(type(uint112).max, type(uint112).max, "x", "y", keccak256("v8"), initData)
        );

        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;
    }
}
