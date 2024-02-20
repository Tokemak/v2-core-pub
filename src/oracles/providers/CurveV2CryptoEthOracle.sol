// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SecurityBase } from "src/security/SecurityBase.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { Errors } from "src/utils/Errors.sol";
import { ICryptoSwapPool } from "src/interfaces/external/curve/ICryptoSwapPool.sol";
import { ICurveV2Swap } from "src/interfaces/external/curve/ICurveV2Swap.sol";

contract CurveV2CryptoEthOracle is SystemComponent, SecurityBase, IPriceOracle, ISpotPriceOracle {
    uint256 public constant FEE_PRECISION = 1e10;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ICurveResolver public immutable curveResolver;

    /**
     * @notice Struct for necessary information for single Curve pool.
     * @param pool The address of the curve pool.
     * @param checkReentrancy uint8 representing a boolean.  0 for false, 1 for true.
     * @param tokenToPrice Address of the token being priced in the Curve pool.
     * @param tokenFromPrice Address of the token being used to price the token in the Curve pool.
     */
    struct PoolData {
        address pool;
        uint8 checkReentrancy;
        address tokenToPrice;
        address tokenFromPrice;
    }

    /**
     * @notice Emitted when token Curve pool is registered.
     * @param lpToken Lp token that has been registered.
     */
    event TokenRegistered(address lpToken);

    /**
     * @notice Emitted when a Curve pool registration is removed.
     * @param lpToken Lp token that has been unregistered.
     */
    event TokenUnregistered(address lpToken);

    /**
     * @notice Thrown when pool returned is not a v2 curve pool.
     * @param curvePool Address of the pool that was attempted to be registered.
     */
    error NotCryptoPool(address curvePool);

    /**
     * @notice Thrown when wrong lp token is returned from CurveResolver.sol.
     * @param providedLP Address of lp token provided in function call.
     * @param queriedLP Address of lp tokens returned from resolver.
     */
    error ResolverMismatch(address providedLP, address queriedLP);

    /**
     * @notice Thrown when lp token is not registered.
     * @param curveLpToken Address of token expected to be registered.
     */
    error NotRegistered(address curveLpToken);

    /**
     * @notice Thrown when a pool with an invalid number of tokens is attempted to be registered.
     * @param numTokens The number of tokens in the pool attempted to be registered.
     */
    error InvalidNumTokens(uint256 numTokens);

    /**
     * @notice Thrown when y and z values do not converge during square root calculation.
     */
    error SqrtError();

    /// @notice Reverse mapping of LP token to pool info.
    mapping(address => PoolData) public lpTokenToPool;

    /// @notice Mapping of pool address to it's LP token.
    mapping(address => address) public poolToLpToken;

    /**
     * @param _systemRegistry Instance of system registry for this version of the system.
     * @param _curveResolver Instance of Curve Resolver.
     */
    constructor(
        ISystemRegistry _systemRegistry,
        ICurveResolver _curveResolver
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_curveResolver), "_curveResolver");

        curveResolver = _curveResolver;
    }

    /**
     * @notice Allows owner of system to register a pool.
     * @dev While the reentrancy check implemented in this contact can technically be used with any token,
     *      it does not make sense to check for reentrancy unless the pool contains ETH, WETH, ERC-677, ERC-777 tokens,
     *      as the known Curve reentrancy vulnerability only works when the caller recieves these tokens.
     *      Therefore, reentrancy checks should only be set to `1` when these tokens are present.  Otherwise we
     *      waste gas claiming admin fees for Curve.
     * @param curvePool Address of CurveV2 pool.
     * @param curveLpToken Address of LP token associated with v2 pool.
     * @param checkReentrancy Whether to check read-only reentrancy on pool.  Set to true for pools containing
     *      ETH or WETH.
     */
    function registerPool(address curvePool, address curveLpToken, bool checkReentrancy) external onlyOwner {
        Errors.verifyNotZero(curvePool, "curvePool");
        Errors.verifyNotZero(curveLpToken, "curveLpToken");
        if (lpTokenToPool[curveLpToken].pool != address(0) || poolToLpToken[curvePool] != address(0)) {
            revert Errors.AlreadyRegistered(curvePool);
        }

        (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap) =
            curveResolver.resolveWithLpToken(curvePool);

        // Only two token pools compatible with this contract.
        if (numTokens != 2) revert InvalidNumTokens(numTokens);
        if (isStableSwap) revert NotCryptoPool(curvePool);
        if (lpToken != curveLpToken) revert ResolverMismatch(curveLpToken, lpToken);

        poolToLpToken[curvePool] = curveLpToken;

        /**
         * Curve V2 pools always price second token in `coins` array in first token in `coins` array.  This means that
         *    if `coins[0]` is Weth, and `coins[1]` is rEth, the price will be rEth as base and weth as quote.
         */
        lpTokenToPool[lpToken] = PoolData({
            pool: curvePool,
            checkReentrancy: checkReentrancy ? 1 : 0,
            tokenToPrice: tokens[1],
            tokenFromPrice: tokens[0]
        });

        emit TokenRegistered(lpToken);
    }

    /**
     * @notice Allows owner of system to unregister curve pool.
     * @param curveLpToken Address of CurveV2 lp token to unregister.
     */
    function unregister(address curveLpToken) external onlyOwner {
        Errors.verifyNotZero(curveLpToken, "curveLpToken");

        address curvePool = lpTokenToPool[curveLpToken].pool;

        if (curvePool == address(0)) revert NotRegistered(curveLpToken);

        // Remove LP token from pool mapping
        delete poolToLpToken[curvePool];
        // Remove pool from LP token mapping
        delete lpTokenToPool[curveLpToken];

        emit TokenUnregistered(curveLpToken);
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");

        PoolData memory poolInfo = lpTokenToPool[token];
        if (poolInfo.pool == address(0)) revert NotRegistered(token);

        ICryptoSwapPool cryptoPool = ICryptoSwapPool(poolInfo.pool);
        address base = poolInfo.tokenToPrice;
        address quote = poolInfo.tokenFromPrice;

        // Checking for read only reentrancy scenario.
        if (poolInfo.checkReentrancy == 1) {
            // This will fail in a reentrancy situation.
            cryptoPool.claim_admin_fees();
        }

        uint256 virtualPrice = cryptoPool.get_virtual_price();
        // `getPriceInQuote` works for both eth pegged and non eth pegged assets.
        uint256 basePrice = systemRegistry.rootPriceOracle().getPriceInQuote(base, quote);
        uint256 ethInQuote = systemRegistry.rootPriceOracle().getPriceInQuote(ETH, quote);

        return (2 * virtualPrice * sqrt(basePrice)) / ethInQuote;
    }

    // solhint-disable max-line-length
    // Adapted from CurveV2 pools, see here:
    // https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/two/CurveCryptoSwap2.vy#L1330
    function sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 10 ** 18) / 2;
        uint256 y = x;

        for (uint256 i = 0; i < 256;) {
            if (z == y) {
                return y;
            }
            y = z;
            z = (x * 10 ** 18 / z + z) / 2;

            unchecked {
                ++i;
            }
        }
        revert SqrtError();
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address
    ) public view returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(pool, "pool");

        address lpToken = poolToLpToken[pool];
        if (lpToken == address(0)) revert NotRegistered(pool);

        (price, actualQuoteToken) = _getSpotPrice(token, pool, lpToken);
    }

    function _getSpotPrice(
        address token,
        address pool,
        address lpToken
    ) internal view returns (uint256 price, address actualQuoteToken) {
        uint256 tokenIndex = 0;
        uint256 quoteTokenIndex = 0;

        PoolData storage poolInfo = lpTokenToPool[lpToken];

        // Find the token and quote token indices
        if (poolInfo.tokenToPrice == token) {
            tokenIndex = 1;
        } else if (poolInfo.tokenFromPrice == token) {
            quoteTokenIndex = 1;
        } else {
            revert NotRegistered(lpToken);
        }

        uint256 dy = ICurveV2Swap(pool).get_dy(tokenIndex, quoteTokenIndex, 10 ** IERC20Metadata(token).decimals());

        /// @dev The fee is dynamically based on current balances; slight discrepancies post-calculation are acceptable
        /// for low-value swaps.
        uint256 fee = ICurveV2Swap(pool).fee();
        price = (dy * FEE_PRECISION) / (FEE_PRECISION - fee);

        actualQuoteToken = quoteTokenIndex == 0 ? poolInfo.tokenFromPrice : poolInfo.tokenToPrice;
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address
    ) external view returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(lpToken, "lpToken");

        totalLPSupply = IERC20Metadata(lpToken).totalSupply();

        PoolData storage tokens = lpTokenToPool[lpToken];
        if (tokens.pool == address(0)) {
            revert NotRegistered(lpToken);
        }

        reserves = new ReserveItemInfo[](2); // This contract only allows CurveV2 pools with two tokens
        uint256[8] memory balances = curveResolver.getReservesInfo(pool);

        (uint256 rawSpotPrice, address actualQuoteToken) = _getSpotPrice(tokens.tokenFromPrice, pool, lpToken);
        reserves[0] = ReserveItemInfo({
            token: tokens.tokenFromPrice,
            reserveAmount: balances[0],
            rawSpotPrice: rawSpotPrice,
            actualQuoteToken: actualQuoteToken
        });

        (rawSpotPrice, actualQuoteToken) = _getSpotPrice(tokens.tokenToPrice, pool, lpToken);
        reserves[1] = ReserveItemInfo({
            token: tokens.tokenToPrice,
            reserveAmount: balances[1],
            rawSpotPrice: rawSpotPrice,
            actualQuoteToken: actualQuoteToken
        });
    }
}
