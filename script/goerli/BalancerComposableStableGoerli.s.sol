// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";

import { ERC20Mock } from "script/contracts/mocks/ERC20Mock.sol";
import { MockRateProvider, IRateProvider } from "script/contracts/mocks/MockRateProvider.sol";
import { IBalancerComposableStableFactory } from "script/interfaces/balancer/IBalancerComposableStableFactory.sol";
import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BalancerComposableStableGoerli is BaseScript {
    // Tokens
    IERC20 public mockSfrxEth;
    IERC20 public mockWstEth;
    IERC20 public mockREth;

    // Rate providers
    IRateProvider public sfrxRateProvider;
    IRateProvider public wstEthRateProvider;
    IRateProvider public rEthRateProvider;

    // Deploy parameters - taken from mainnet contract.
    string public poolName = "wstETH-rETH-sfrxETH-BPT";
    string public poolSymbol = "wstETH-rETH-sfrxETH-BPT";
    uint256 public amplification = 2000;
    uint256[] public tokenCacheDurations = [10_800, 10_800, 10_800];
    IRateProvider[] public rateProviders;
    IERC20[] public tokens;
    bool public exemptFromYieldFee = false;
    uint256 public swapFeePercentage = 400_000_000_000_000;
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        console.log("Owner: ", owner);

        // Create tokens, ERC20 mocks.
        mockSfrxEth = new ERC20Mock("Mock sfrxEth", "mSfrxEth");
        mockWstEth = ERC20Mock(constants.tokens.wstEth);
        mockREth = new ERC20Mock("Mock rEth", "mREth");

        ERC20Mock(address(mockSfrxEth)).mint(owner, 100_000e18);
        ERC20Mock(address(mockWstEth)).mint(owner, 100_000e18);
        ERC20Mock(address(mockREth)).mint(owner, 100_000e18);

        console.log("sfrxEth: ", address(mockSfrxEth));
        console.log("wstEth: ", address(mockWstEth));
        console.log("rEth", address(mockREth));

        // Push tokens to array - to be sorted later.
        tokens.push(mockSfrxEth);
        tokens.push(mockWstEth);
        tokens.push(mockREth);

        // Create rate providers, mocks.
        sfrxRateProvider = IRateProvider(new MockRateProvider(address(mockSfrxEth), 1e18));
        wstEthRateProvider = IRateProvider(new MockRateProvider(address(mockWstEth), 1e18));
        rEthRateProvider = IRateProvider(new MockRateProvider(address(mockREth), 1e18));

        console.log("sfrxEth rate provider: ", address(sfrxRateProvider));
        console.log("wstEth rate provider: ", address(wstEthRateProvider));
        console.log("rEth rate provider: ", address(rEthRateProvider));

        // Push rate providers to array - to be sorted later.
        rateProviders.push(sfrxRateProvider);
        rateProviders.push(wstEthRateProvider);
        rateProviders.push(rEthRateProvider);

        //
        // Sort arrays, Balancer requires this.  See BAL#101 error.
        //

        // Set first token as smallest.  Rate provider array is tracked by index, does not need to be in numerical order
        //      like tokens do.
        IERC20 smallest = tokens[0];
        IRateProvider smallestRateProviderIndexMatch = rateProviders[0];
        for (uint256 i = 1; i < 3; ++i) {
            IERC20 currentToken = tokens[i];
            IRateProvider currentRateProvider = rateProviders[i];
            // If the current token is smaller than the token set as `smallest`, swap the positions in the array for
            //      both token and rate provider.
            if (currentToken < smallest) {
                tokens[0] = currentToken;
                tokens[i] = smallest;

                rateProviders[0] = currentRateProvider;
                rateProviders[i] = smallestRateProviderIndexMatch;

                smallest = currentToken;
                smallestRateProviderIndexMatch = currentRateProvider;
            }
        }
        // If the token at the second index is larger than the token at the final index, swap.
        if (tokens[1] > tokens[2]) {
            IERC20 larger = tokens[1];
            IRateProvider largerRateProviderIndexMatch = rateProviders[1];

            tokens[1] = tokens[2];
            rateProviders[1] = rateProviders[2];

            tokens[2] = larger;
            rateProviders[2] = largerRateProviderIndexMatch;
        }

        // Create pool.
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(
            IBalancerComposableStableFactory(constants.ext.balancerComposableStableFactory).create(
                poolName,
                poolSymbol,
                tokens,
                amplification,
                rateProviders,
                tokenCacheDurations,
                exemptFromYieldFee,
                swapFeePercentage,
                owner,
                keccak256("toke-bal-comp-1")
            )
        );

        console.log("Pool created: ", address(pool));

        vm.stopBroadcast();
    }
}
