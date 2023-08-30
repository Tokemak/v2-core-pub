// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IMavFactory {
    /// @dev Create new Mav pool.
    function create(
        uint256 fee,
        uint256 tickSpacing,
        int256 lookBack,
        int32 activeTick,
        IERC20 tokenA,
        IERC20 tokenB
    ) external returns (address);
}
