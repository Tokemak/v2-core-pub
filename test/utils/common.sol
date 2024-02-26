// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable-next-line no-console
import { console2 as console } from "forge-std/console2.sol";

library Utils {
    function getContractSize(address _addr) public view returns (uint256) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(_addr)
        }
        return size;
    }
}
