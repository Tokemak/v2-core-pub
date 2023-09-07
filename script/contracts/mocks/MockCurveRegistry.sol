// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

import { ICurvePool } from "script/interfaces/curve/ICurvePool.sol";

// solhint-disable func-name-mixedcase

contract MockCurveRegistry is Ownable {
    struct Pool {
        address lpToken;
        uint8 numTokens;
        address[8] tokens;
    }

    // Mapping of pool address to Pool struct.
    mapping(address => Pool) public pools;

    function setPool(address _pool, address _lpToken, uint8 _numTokens) external onlyOwner {
        address[8] memory tokens;

        for (uint256 i = 0; i < _numTokens; ++i) {
            tokens[i] = ICurvePool(_pool).coins(i);
        }

        pools[_pool] = Pool({ lpToken: _lpToken, numTokens: _numTokens, tokens: tokens });
    }

    function get_coins(address poolAddress) external view returns (address[8] memory) {
        return pools[poolAddress].tokens;
    }

    function get_n_coins(address poolAddress) external view returns (uint256) {
        return pools[poolAddress].numTokens;
    }

    function get_lp_token(address poolAddress) external view returns (address) {
        return pools[poolAddress].lpToken;
    }
}
