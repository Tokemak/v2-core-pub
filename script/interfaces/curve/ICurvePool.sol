// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

//solhint-disable func-name-mixedcase

interface ICurvePool {
    function coins(uint256 i) external view returns (address);

    function add_liquidity(uint256[2] memory amounts, uint256 mintMintAmount) external payable returns (uint256);
}
