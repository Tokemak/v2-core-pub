// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { hevm } from "./Hevm.sol";

/// @title Log to the file system
contract FileSystemLogger {
    function fsLog(string memory data) public {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "./utils/echidnaLogger.sh";
        inputs[2] = data;

        try hevm.ffi(inputs) { } catch { }
    }

    function toString(address account) public pure returns (string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(int8 _i) public pure returns (string memory) {
        return string.concat((-_i < 0 ? "-" : ""), toString(uint256(uint8(_i * -1))));
    }

    function toString(uint256 _i) public pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bytesStr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bytesStr[k] = b1;
            _i /= 10;
        }
        return string(bytesStr);
    }

    function toString(bytes memory data) public pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
