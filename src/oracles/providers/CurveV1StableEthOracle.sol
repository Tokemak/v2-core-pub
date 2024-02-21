// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Errors } from "src/utils/Errors.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { ICurveOwner } from "src/interfaces/external/curve/ICurveOwner.sol";
import { ICurveV1StableSwap } from "src/interfaces/external/curve/ICurveV1StableSwap.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { Arrays } from "src/utils/Arrays.sol";

/// @title Price oracle for Curve StableSwap pools
/// @dev getPriceEth is not a view fn to support reentrancy checks. Don't actually change state.
contract CurveV1StableEthOracle is SystemComponent, SecurityBase, IPriceOracle, ISpotPriceOracle {
    ICurveResolver public immutable curveResolver;
    uint256 public constant FEE_PRECISION = 1e10;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // solhint-disable-next-line var-name-mixedcase
    address public immutable WETH;

    struct PoolData {
        address pool;
        uint8 checkReentrancy;
    }

    event TokenRegistered(address lpToken);
    event TokenUnregistered(address lpToken);

    error NotStableSwap(address curvePool);
    error NotRegistered(address curveLpToken);
    error InvalidPrice(address token, uint256 price);
    error ResolverMismatch(address providedLP, address queriedLP);

    /// @notice Curve LP tokens and their underlying tokens
    /// @dev lpToken => erc20[]
    mapping(address => address[]) public lpTokenToUnderlying;

    /// @notice Reverse mapping of LP token to pool info
    mapping(address => PoolData) public lpTokenToPool;

    /// @notice Mapping of pool address to it's LP token
    mapping(address => address) public poolToLpToken;

    constructor(
        ISystemRegistry _systemRegistry,
        ICurveResolver _curveResolver
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_curveResolver), "_curveResolver");

        curveResolver = _curveResolver;
        WETH = address(_systemRegistry.weth());
    }

    /// @notice Register a Curve LP token to this oracle
    /// @dev Double checks pool+lp against on-chain query. Only use with StableSwap pools.
    /// @dev Pool containing Eth, Weth, ERC-677, ERC-777 tokens should all be registered for reentrancy checks.
    /// @param curvePool address of the Curve pool related to the LP token
    /// @param curveLpToken address of the LP token we'll be looking up prices for
    /// @param checkReentrancy whether or not we should check for read-only reentrancy
    function registerPool(address curvePool, address curveLpToken, bool checkReentrancy) external onlyOwner {
        Errors.verifyNotZero(curvePool, "curvePool");
        Errors.verifyNotZero(curveLpToken, "curveLpToken");

        (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap) =
            curveResolver.resolveWithLpToken(curvePool);

        if (lpTokenToPool[lpToken].pool != address(0) || poolToLpToken[curvePool] != address(0)) {
            revert Errors.AlreadyRegistered(curvePool);
        }

        // This oracle uses the min-price approach for finding the current value of tokens
        // and only applies to stable swap pools. The resolver will resolve both stable and
        // crypto swap pools so we want to be sure only the correct type gets in.
        if (!isStableSwap) {
            revert NotStableSwap(curvePool);
        }

        // Make sure the data we were working with off-chain during registration matches
        // what we get if we query it on-chain, expectation check
        if (lpToken != curveLpToken) {
            revert ResolverMismatch(curveLpToken, lpToken);
        }

        for (uint256 i = 0; i < numTokens;) {
            lpTokenToUnderlying[lpToken].push(tokens[i]);

            unchecked {
                ++i;
            }
        }
        // Reverse mapping setup
        lpTokenToPool[lpToken] = PoolData({ pool: curvePool, checkReentrancy: checkReentrancy ? 1 : 0 });
        // Direct mapping setup
        poolToLpToken[curvePool] = curveLpToken;

        emit TokenRegistered(lpToken);
    }

    /// @notice Unregister a Curve Lp token from the oracle
    /// @dev Must already exist. More lenient than register with expectation checks, it's already in,
    /// assume you know what you're doing
    /// @param curveLpToken token to unregister
    function unregister(address curveLpToken) external onlyOwner {
        Errors.verifyNotZero(curveLpToken, "curveLpToken");

        // You're calling unregister so you're expecting it to be here
        // Stopping if not so you can reevaluate
        if (lpTokenToUnderlying[curveLpToken].length == 0) {
            revert NotRegistered(curveLpToken);
        }

        address curvePool = lpTokenToPool[curveLpToken].pool;
        delete poolToLpToken[curvePool];

        delete lpTokenToUnderlying[curveLpToken];
        delete lpTokenToPool[curveLpToken];

        emit TokenUnregistered(curveLpToken);
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(address token) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");

        address[] memory tokens = lpTokenToUnderlying[token];

        uint256 minPrice = type(uint256).max;
        uint256 nTokens = tokens.length;

        if (nTokens == 0) {
            revert NotRegistered(token);
        }

        PoolData memory poolInfo = lpTokenToPool[token];
        ICurveV1StableSwap pool = ICurveV1StableSwap(poolInfo.pool);

        /**
         * We're in a V1 pool and we'll be reading the virtual price later
         *      make sure we're not in a read-only reentrancy scenario
         *
         * This check can be done for any token, although the reentrancy attack only
         *      applies to pools containing Eth, Weth, ERC-677 or ERC-777 tokens.
         */
        if (poolInfo.checkReentrancy == 1) {
            // This will fail in reentrancy
            ICurveOwner(pool.owner()).withdraw_admin_fees(address(pool));
        }

        for (uint256 i = 0; i < nTokens;) {
            address iToken = tokens[i];

            // Our prices are always in 1e18
            uint256 tokenPrice = systemRegistry.rootPriceOracle().getPriceInEth(iToken);
            if (tokenPrice < minPrice) {
                minPrice = tokenPrice;
            }

            unchecked {
                ++i;
            }
        }

        // If it's still the default price we set, something went wrong
        if (minPrice == type(uint256).max) {
            revert InvalidPrice(token, type(uint256).max);
        }

        price = (minPrice * pool.get_virtual_price() / 1e18);
    }

    function getLpTokenToUnderlying(address lpToken) external view returns (address[] memory tokens) {
        uint256 len = lpTokenToUnderlying[lpToken].length;
        tokens = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            tokens[i] = lpTokenToUnderlying[lpToken][i];
        }
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) public view returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(pool, "pool");

        address lpToken = poolToLpToken[pool];
        address[] memory tokens = lpTokenToUnderlying[lpToken];

        uint256 nTokens = tokens.length;
        if (nTokens == 0) {
            revert NotRegistered(lpToken);
        }

        (price, actualQuoteToken) = _getSpotPrice(token, pool, tokens, requestedQuoteToken);
    }

    function _getSpotPrice(
        address token,
        address pool,
        address[] memory tokens,
        address requestedQuoteToken
    ) internal view returns (uint256 price, address actualQuoteToken) {
        int256 tokenIndex = -1;
        int256 quoteTokenIndex = -1;

        // Find the token and quote token indices
        uint256 nTokens = tokens.length;
        for (uint256 i = 0; i < nTokens; ++i) {
            address t = tokens[i];

            if (t == ETH) {
                t = WETH;
            }

            if (t == token) {
                tokenIndex = int256(i);
            } else if (t == requestedQuoteToken) {
                quoteTokenIndex = int256(i);
            }

            // Break out of the loop if both indices are found.
            if (tokenIndex != -1 && quoteTokenIndex != -1) {
                break;
            }
        }

        if (tokenIndex == -1) revert NotRegistered(token);

        // Selecting a different quote token if the requested one is not found.
        if (quoteTokenIndex == -1) {
            quoteTokenIndex = tokenIndex == 0 ? int256(1) : int256(0);
        }

        uint256 dy = ICurveV1StableSwap(pool).get_dy(
            int128(tokenIndex), int128(quoteTokenIndex), 10 ** IERC20Metadata(token).decimals()
        );

        uint256 fee = ICurveV1StableSwap(pool).fee();
        price = (dy * FEE_PRECISION) / (FEE_PRECISION - fee);

        actualQuoteToken = ICurveV1StableSwap(pool).coins(uint256(quoteTokenIndex));

        // If the quote token is ETH, we convert it to WETH.
        if (actualQuoteToken == ETH) {
            actualQuoteToken = WETH;
        }
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken
    ) external view returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(lpToken, "lpToken");
        Errors.verifyNotZero(quoteToken, "quoteToken");

        totalLPSupply = IERC20Metadata(lpToken).totalSupply();

        address[] storage tokens = lpTokenToUnderlying[lpToken];
        uint256 nTokens = tokens.length;
        if (nTokens == 0) {
            revert NotRegistered(lpToken);
        }

        uint256[8] memory balances = curveResolver.getReservesInfo(pool);
        reserves = new ReserveItemInfo[](nTokens);
        for (uint256 i = 0; i < nTokens; ++i) {
            address token = tokens[i];

            if (token == ETH) {
                token = WETH;
            }

            (uint256 rawSpotPrice, address actualQuoteToken) = _getSpotPrice(token, pool, tokens, quoteToken);

            reserves[i] = ReserveItemInfo({
                token: token,
                reserveAmount: balances[i],
                rawSpotPrice: rawSpotPrice,
                actualQuoteToken: actualQuoteToken
            });
        }
    }
}
