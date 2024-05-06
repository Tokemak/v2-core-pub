// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { TestERC20 } from "test/mocks/TestERC20.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { Vm } from "forge-std/Vm.sol";

contract TokenReturnSolver is IERC3156FlashBorrower {
    Vm private vm;

    constructor(Vm _vm) {
        vm = _vm;
    }

    function buildDataForDvIn(address dv, uint256 returnAmount) public view returns (bytes memory) {
        return abi.encode(returnAmount, IDestinationVault(dv).underlying(), "ERC3156FlashBorrower.onFlashLoan");
    }

    function buildForIdleIn(IAutopool vault, uint256 returnAmount) public view returns (bytes memory) {
        return abi.encode(returnAmount, vault.asset(), "ERC3156FlashBorrower.onFlashLoan");
    }

    function buildDataForDvIn(
        address dv,
        uint256 returnAmount,
        string memory valueToHash
    ) public view returns (bytes memory) {
        return abi.encode(returnAmount, IDestinationVault(dv).underlying(), valueToHash);
    }

    function buildForIdleIn(
        IAutopool vault,
        uint256 returnAmount,
        string memory valueToHash
    ) public view returns (bytes memory) {
        return abi.encode(returnAmount, vault.asset(), valueToHash);
    }

    function onFlashLoan(address, address, uint256, uint256, bytes memory data) external returns (bytes32) {
        (uint256 ret, address token, string memory hashVal) = abi.decode(data, (uint256, address, string));

        if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) {
            vm.deal(address(this), ret);
            IWETH9(token).deposit{ value: ret }();
            IWETH9(token).transfer(msg.sender, ret);
        } else {
            TestERC20(token).mint(msg.sender, ret);
        }

        return keccak256(abi.encodePacked(hashVal));
    }
}
