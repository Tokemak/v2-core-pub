// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "./IRateProvider.sol";

interface IBalancerMetaStableFactory {
    /// @dev Creates a Balancer MetaStable pool
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256 amplificationParameter,
        IRateProvider[] memory rateProviders,
        uint256[] memory priceRateCacheDuration,
        uint256 swapFeePercentage,
        bool oracleEnabled,
        address owner
    ) external returns (address);
}
