// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IBalancerRateProvider {
    /**
     * @notice Returns the price of a unit of osToken (e.g price of osETH in ETH)
     * @return The price of a unit of osToken (with 18 decimals)
     */
    function getRate() external view returns (uint256);
}
