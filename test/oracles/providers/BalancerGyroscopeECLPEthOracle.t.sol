// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IBasePool } from "src/interfaces/external/balancer/IBasePool.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { BalancerGyroscopeECLPEthOracle } from "src/oracles/providers/BalancerGyroscopeECLPEthOracle.sol";
import {
    BAL_VAULT,
    WETH_MAINNET,
    WSTETH_MAINNET,
    WSTETH_WETH_GYRO_POOL,
    USDT_GYD_GYRO_POOL
} from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase,private-vars-leading-underscore

contract BalancerGyroscopeECLPEthOracleTests is Test {
    IBalancerVault internal constant VAULT = IBalancerVault(BAL_VAULT);

    IRootPriceOracle internal rootPriceOracle;
    ISystemRegistry internal systemRegistry;
    BalancerGyroscopeECLPEthOracle internal oracle;

    event ReceivedPrice();

    function setUp() public {
        // 19_661_436, block where failing
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_220_662);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerGyroscopeECLPEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
        assertEq("balGyro", oracle.getDescription());
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}

contract GetSpotPrice is BalancerGyroscopeECLPEthOracleTests {
    function test_RevertsIf_TokenDNEInPool() public {
        address fakeToken = makeAddr("FAKE_TOKEN");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, fakeToken));
        oracle.getSpotPrice(fakeToken, WSTETH_WETH_GYRO_POOL, address(1));
    }

    function test_ReturnsCorrectPrice_Token0InToken1() public {
        (IERC20[] memory tokens,) = _getTokensAndBalances(WSTETH_WETH_GYRO_POOL);
        address token0 = address(tokens[0]);
        address token1 = address(tokens[1]);

        // Use swap via vault to validate spot price returned.  Checked that pinned block is not in extreme state
        uint256 expectedPrice = _swapAmount(WSTETH_WETH_GYRO_POOL, token0, token1, 1e18, false);
        (uint256 returnedPrice, address actualQuote) = oracle.getSpotPrice(token0, WSTETH_WETH_GYRO_POOL, address(1));

        // .1% tolerance, expect these to be close
        (uint256 upper, uint256 lower) = _getPriceBounds(expectedPrice, 10);

        assertEq(token1, actualQuote);
        assertLt(returnedPrice, upper);
        assertGt(returnedPrice, lower);
    }

    function test_ReturnsCorrectPrice_Token1InToken0() public {
        (IERC20[] memory tokens,) = _getTokensAndBalances(WSTETH_WETH_GYRO_POOL);
        address token0 = address(tokens[0]);
        address token1 = address(tokens[1]);

        // Use swap via vault to validate spot price returned.  Checked that pinned block is not in extreme state
        uint256 expectedPrice = _swapAmount(WSTETH_WETH_GYRO_POOL, token1, token0, 1e18, false);
        (uint256 returnedPrice, address actualQuote) = oracle.getSpotPrice(token1, WSTETH_WETH_GYRO_POOL, address(1));

        // .1% tolerance, expect these to be close
        (uint256 upper, uint256 lower) = _getPriceBounds(expectedPrice, 10);

        assertEq(token0, actualQuote);
        assertLt(returnedPrice, upper);
        assertGt(returnedPrice, lower);
    }

    function test_ReturnsCorrectPrice_TokensWithDifferingDecimals() public {
        (IERC20[] memory tokens,) = _getTokensAndBalances(USDT_GYD_GYRO_POOL);
        address token0 = address(tokens[0]); // usdt
        address token1 = address(tokens[1]); // gyd

        // USDT tokenIn, amount adjusted
        uint256 expectedPriceToken0ToToken1 = _swapAmount(USDT_GYD_GYRO_POOL, token0, token1, 1e6, false);
        (uint256 returnedPriceToken0ToToken1, address actualQuote0) =
            oracle.getSpotPrice(token0, USDT_GYD_GYRO_POOL, address(1));

        // .1% tolerance, expect these to be close
        (uint256 upper, uint256 lower) = _getPriceBounds(expectedPriceToken0ToToken1, 10);

        emit log_uint(expectedPriceToken0ToToken1);
        emit log_uint(returnedPriceToken0ToToken1);

        assertEq(token1, actualQuote0);
        assertLt(returnedPriceToken0ToToken1, upper);
        assertGt(returnedPriceToken0ToToken1, lower);

        uint256 expectedPriceToken1ToToken0 = _swapAmount(USDT_GYD_GYRO_POOL, token1, token0, 1e18, false);
        (uint256 returnedPriceToken1ToToken0, address actualQuote1) =
            oracle.getSpotPrice(token1, USDT_GYD_GYRO_POOL, address(1));

        // .1% tolerance, expect these to be close
        (upper, lower) = _getPriceBounds(expectedPriceToken1ToToken0, 10);

        emit log_uint(expectedPriceToken1ToToken0);
        emit log_uint(returnedPriceToken1ToToken0);

        assertEq(token0, actualQuote1);
        assertLt(returnedPriceToken1ToToken0, upper);
        assertGt(returnedPriceToken1ToToken0, lower);
    }

    // The idea here is to get the pool to as close to 100% of one asset as we can and make sure that the price returns
    //  corresponds with the pool price bounds displayed on the Gyro UI.
    function test_PoolReturnsReasonablePrice_AtPoolBounds() public {
        (IERC20[] memory tokens, uint256[] memory balances) = _getTokensAndBalances(WSTETH_WETH_GYRO_POOL);
        address token0 = address(tokens[0]);
        address token1 = address(tokens[1]);

        // Snapshot makes swapping in other direction easier
        uint256 snapshot = vm.snapshot();

        // Swap leaves less than 1e18 weth in pool
        _swapAmount(WSTETH_WETH_GYRO_POOL, token0, token1, 355.5e18, false);
        (, balances) = _getTokensAndBalances(WSTETH_WETH_GYRO_POOL);

        assertLt(balances[1], 1e18);

        // Checking that swap pricing method would not work in this scenario
        _swapAmount(WSTETH_WETH_GYRO_POOL, token0, token1, 1e18, true);

        (uint256 price, address quote) = oracle.getSpotPrice(token0, WSTETH_WETH_GYRO_POOL, address(1));

        // Min pool price taken from Gyro UI
        uint256 scaledUIPrice = 1.1698e18;

        // Get price bounds within .1%
        (uint256 upper, uint256 lower) = _getPriceBounds(scaledUIPrice, 10);

        assertEq(token1, quote);
        assertLt(price, upper);
        assertGt(price, lower);

        // Revert EVM  state
        vm.revertTo(snapshot);

        _swapAmount(WSTETH_WETH_GYRO_POOL, token1, token0, 1485e18, false);
        (, balances) = _getTokensAndBalances(WSTETH_WETH_GYRO_POOL);

        assertLt(balances[0], 1e18);

        // Check that swap pricing does not work here
        _swapAmount(WSTETH_WETH_GYRO_POOL, token1, token0, 1e18, true);

        // Swap price from token1 -> token0 is the one that does not work in this scenario, so price token1
        (price, quote) = oracle.getSpotPrice(token1, WSTETH_WETH_GYRO_POOL, address(1));

        // UI scaling adjusting for token being priced being token1
        uint256 scaledUIPriceAdjustedForToken1 = uint256(1e36) / uint256(1.1722e18);

        (upper, lower) = _getPriceBounds(scaledUIPriceAdjustedForToken1, 10);

        assertEq(token0, quote);
        assertLt(price, upper);
        assertGt(price, lower);
    }

    /// @dev Swaps amount of tokenIn for tokenOut on pool.  Returns tokenOut received.
    /// @dev Takes care of dealing tokens and approvals.
    function _swapAmount(
        address poolAddress,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool checkRevert
    ) internal returns (uint256) {
        deal(tokenIn, address(this), amount);
        // Using safeIncreaseAllowance for USDT test
        SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(VAULT), amount);

        IBasePool pool = IBasePool(poolAddress);
        bytes32 poolId = pool.getPoolId();
        IBalancerVault.SingleSwap memory swap = IBalancerVault.SingleSwap({
            poolId: poolId,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: tokenIn,
            assetOut: tokenOut,
            amount: amount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds =
            IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        // Used in situation that we are checking for vault swap failure
        if (checkRevert) {
            vm.expectRevert("GYR#357");
        }
        uint256 amountReceived = VAULT.swap(
            swap,
            funds,
            0, // Limit for taken from pool on GIVEN_IN swap
            block.timestamp
        );

        return amountReceived * 1e18 / (1e18 - pool.getSwapFeePercentage());
    }

    /// @dev Get tokens in pool from vault.  Tokens sorted, this returns them in order.
    function _getTokensAndBalances(address pool)
        internal
        view
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        (tokens, balances,) = VAULT.getPoolTokens(IBasePool(pool).getPoolId());
    }

    /// @param expectedPrice Price calculated via swap
    /// @param tolerancePercent Percentage tolerance.  10_000 = 100%, 100 = 1%, etc.
    function _getPriceBounds(
        uint256 expectedPrice,
        uint256 tolerancePercent
    ) internal pure returns (uint256 upper, uint256 lower) {
        uint256 toleranceValue = expectedPrice * tolerancePercent / 10_000;

        upper = expectedPrice + toleranceValue;
        lower = expectedPrice - toleranceValue;
    }
}

contract GetSafeSpotPriceInfo is BalancerGyroscopeECLPEthOracleTests {
    function test_getSafeSpotPriceInfo() public {
        deal(address(WSTETH_MAINNET), address(this), 20 * 1e18);
        deal(address(WETH_MAINNET), address(this), 20 * 1e18);
        deal(address(this), 3 ether);

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            oracle.getSafeSpotPriceInfo(WSTETH_WETH_GYRO_POOL, WSTETH_WETH_GYRO_POOL, WETH_MAINNET);

        assertEq(reserves.length, 2, "rlen");
        assertEq(totalLPSupply, 1_867_027_268_022_323_573_987, "totalLPSupply");
        assertEq(reserves[0].token, WSTETH_MAINNET, "token0");
        assertEq(reserves[0].reserveAmount, 1_267_429_175_143_065_280_189, "reserveAmount0");
        assertEq(reserves[0].rawSpotPrice, 1_171_315_251_393_355_875, "rawSpotPrice0");
        assertEq(reserves[0].actualQuoteToken, WETH_MAINNET, "actualQuoteToken0");
        assertEq(reserves[1].token, WETH_MAINNET, "token1");
        assertEq(reserves[1].reserveAmount, 416_495_043_929_755_302_818, "reserveAmount1");
        assertEq(reserves[1].rawSpotPrice, 853_741_124_612_212_457, "rawSpotPrice1");
        assertEq(reserves[1].actualQuoteToken, WSTETH_MAINNET, "actualQuoteToken1");
    }
}
