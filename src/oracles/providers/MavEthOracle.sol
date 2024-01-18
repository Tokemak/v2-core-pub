// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { IPoolPositionDynamicSlim } from "src/interfaces/external/maverick/IPoolPositionDynamicSlim.sol";
import { Errors } from "src/utils/Errors.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { IPoolInformation } from "src/interfaces/external/maverick/IPoolInformation.sol";

//slither-disable-start similar-names
contract MavEthOracle is SystemComponent, IPriceOracle, SecurityBase, ISpotPriceOracle {
    /// @notice Emitted when new maximum bin width is set.
    event MaxTotalBinWidthSet(uint256 newMaxBinWidth);

    /// @notice Emitted when Maverick PoolInformation contract is set.
    event PoolInformationSet(address poolInformation);

    /// @notice Thrown when the total width of all bins being priced exceeds the max.
    error TotalBinWidthExceedsMax();

    /// @notice Thrown when token is not in pool.
    error InvalidToken();

    // 100 = 1% spacing, 10 = .1% spacing, 1 = .01% spacing etc.
    uint256 public maxTotalBinWidth = 50;

    /// @notice The PoolInformation Maverick contract.
    IPoolInformation public poolInformation;

    constructor(
        ISystemRegistry _systemRegistry,
        address _poolInformation
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "priceOracle");

        Errors.verifyNotZero(_poolInformation, "_poolInformation");
        poolInformation = IPoolInformation(_poolInformation);
    }

    /**
     * @notice Gives ability to set total bin width to system owner.
     * @param _maxTotalBinWidth New max bin width.
     */
    function setMaxTotalBinWidth(uint256 _maxTotalBinWidth) external onlyOwner {
        Errors.verifyNotZero(_maxTotalBinWidth, "_maxTotalbinWidth");
        maxTotalBinWidth = _maxTotalBinWidth;

        emit MaxTotalBinWidthSet(_maxTotalBinWidth);
    }

    /// @notice Gives ability to set PoolInformation contract to system owner
    function setPoolInformation(address _poolInformation) external onlyOwner {
        Errors.verifyNotZero(_poolInformation, "_poolInformation");
        poolInformation = IPoolInformation(_poolInformation);

        emit PoolInformationSet(_poolInformation);
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address _boostedPosition) external returns (uint256) {
        // slither-disable-start similar-names
        Errors.verifyNotZero(_boostedPosition, "_boostedPosition");

        IPoolPositionDynamicSlim boostedPosition = IPoolPositionDynamicSlim(_boostedPosition);
        IPool pool = IPool(boostedPosition.pool());

        Errors.verifyNotZero(address(pool), "pool");

        _checkSafeWidth(pool, boostedPosition);

        // Get reserves in boosted position.
        (uint256 reserveTokenA, uint256 reserveTokenB) = boostedPosition.getReserves();

        // Get total supply of lp tokens from boosted position.
        uint256 boostedPositionTotalSupply = boostedPosition.totalSupply();

        IRootPriceOracle rootPriceOracle = systemRegistry.rootPriceOracle();

        // Price pool tokens.
        uint256 priceInEthTokenA = rootPriceOracle.getPriceInEth(address(pool.tokenA()));
        uint256 priceInEthTokenB = rootPriceOracle.getPriceInEth(address(pool.tokenB()));

        // Calculate total value of each token in boosted position.
        uint256 totalBoostedPositionValueTokenA = reserveTokenA * priceInEthTokenA;
        uint256 totalBoostedPositionValueTokenB = reserveTokenB * priceInEthTokenB;

        // Return price of lp token in boosted position.
        return (totalBoostedPositionValueTokenA + totalBoostedPositionValueTokenB) / boostedPositionTotalSupply;
        // slither-disable-end similar-names
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address poolAddress,
        address
    ) public returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(poolAddress, "poolAddress");

        IPool pool = IPool(poolAddress);

        address tokenA = address(pool.tokenA());
        address tokenB = address(pool.tokenB());

        // Determine if the input token is tokenA
        bool isTokenA = token == tokenA;

        // Determine actualQuoteToken as the opposite of the input token
        actualQuoteToken = isTokenA ? tokenB : tokenA;

        // Validate if the input token is either tokenA or tokenB
        if (!isTokenA && token != tokenB) revert InvalidToken();

        price = _getSpotPrice(token, pool, isTokenA);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        // solhint-disable-next-line no-unused-vars
        address pool,
        // solhint-disable-next-line no-unused-vars
        address _boostedPosition,
        address // we omit quoteToken as we get pricing info from the pool.
            // It's aligned with the requested quoteToken in RootPriceOracle.getRangePricesLP
            // solhint-disable-next-line no-unused-vars
    ) external returns (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) {
        revert Errors.NotImplemented(); // Postponed until we have Maverick added to the system.
    }

    /// @dev This function gets price using Maverick's `PoolInformation` contract
    function _getSpotPrice(address token, IPool pool, bool isTokenA) private returns (uint256 price) {
        price = poolInformation.calculateSwap(
            pool,
            uint128(10 ** IERC20Metadata(token).decimals()), // amount
            isTokenA, // tokenAIn
            false, // exactOutput
            0 // sqrtPriceLimit
        );

        // Maverick Fee is in 1e18.
        // https://docs.mav.xyz/guides/technical-reference/pool#fn-fee
        price = (price * 1e18) / (1e18 - pool.fee());
    }

    ///@dev Check that total width of all bins in position does not exceed what we deem safe
    function _checkSafeWidth(IPool pool, IPoolPositionDynamicSlim boostedPosition) private {
        if (pool.tickSpacing() * boostedPosition.allBinIds().length > maxTotalBinWidth) {
            revert TotalBinWidthExceedsMax();
        }
    }
}
//slither-disable-end similar-names
