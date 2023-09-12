// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";

import { IBalancerMetaStableFactory } from "script/interfaces/balancer/IBalancerMetaStableFactory.sol";
import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { ERC20Mock } from "script/contracts/mocks/ERC20Mock.sol";
import { MockRateProvider, IRateProvider } from "script/contracts/mocks/MockRateProvider.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BalancerMetaStableGoerli is BaseScript {
    // Tokens
    IERC20 public weth;
    IERC20 public wstEth;

    // solhint-disable max-line-length
    /**
     * Rate provider not required for Eth pegged tokens. See
     *     https://github.com/balancer/docs-developers/blob/main/resources/deploy-pools-from-factory/creation/metastable-pool.md#rateproviders
     */
    // solhint-enable max-line-length
    IRateProvider public wethRateProvider = IRateProvider(address(0));
    IRateProvider public wstEthRateProvider;

    // Deploy params - taken from mainnet contract.
    string public name = "Balancer stETH Stable Pool";
    string public symbol = "B-stETH-STABLE";
    IERC20[] public tokens;
    uint256 public amplification = 50;
    IRateProvider[] public rateProviders;
    uint256[] public rateDurations = [0, 10_800]; // Set this here because values, order of other arrays known
    uint256 public swapFeePercentage = 400_000_000_000_000;
    bool public oracleEnabled = true;
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        console.log("Owner: ", owner);

        // Create tokens that need to be created, wrap others that do not - ERC20 mocks
        weth = IERC20(constants.tokens.weth);
        wstEth = IERC20(constants.tokens.wstEth);

        console.log("Weth address: ", address(weth));
        console.log("wstEth address: ", address(wstEth));

        // Push tokens to array, will be sorted later.
        tokens.push(weth);
        tokens.push(wstEth);

        // TODO: Change to deployed wstEth rate provider once composable stable pool deployed.
        // Create mock rate providers.
        wstEthRateProvider = IRateProvider(new MockRateProvider(address(wstEth), 1e18));

        console.log("WstEth rate provider: ", address(wstEthRateProvider));
        console.log("Weth rate provider", address(wethRateProvider));

        // Push rate providers to array
        rateProviders.push(wethRateProvider);
        rateProviders.push(wstEthRateProvider);

        // Sort arrays.  Balancer requires pool tokens in numerical order.
        if (tokens[0] > tokens[1]) {
            IERC20 largerToken = tokens[0];
            IRateProvider matchingIndexRateProvider = rateProviders[0];
            uint256 matchingIndexDuration = rateDurations[0];

            tokens[0] = tokens[1];
            tokens[1] = largerToken;

            rateProviders[0] = rateProviders[1];
            rateProviders[1] = matchingIndexRateProvider;

            rateDurations[0] = rateDurations[1];
            rateDurations[1] = matchingIndexDuration;
        }

        // Create pool.
        address pool = IBalancerMetaStableFactory(constants.ext.balancerMetaStableFactor).create(
            name, symbol, tokens, amplification, rateProviders, rateDurations, swapFeePercentage, oracleEnabled, owner
        );

        console.log("Pool: ", pool);
    }
}
