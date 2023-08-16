// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { ERC20Mock } from "script/mocks/ERC20Mock.sol";
import { MockRateProvider, IRateProvider } from "script/mocks/MockRateProvider.sol";
import { IBalancerMetaStableFactory } from "script/interfaces/external/IBalancerMetaStableFactory.sol";
import { BALANCER_METASTABLE_FACTORY_GOERLI } from "script/utils/Addresses.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BalancerMetaStableGoerli is Script {
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
    address public owner = vm.addr(vm.envUint("GOERLI_PRIVATE_KEY"));

    function run() external {
        vm.startBroadcast(vm.envUint("GOERLI_PRIVATE_KEY"));

        console.log("Owner: ", owner);

        // Create tokens that need to be created, wrap others that do not - ERC20 mocks
        weth = IERC20(new ERC20Mock("Tokemak Controllred Weth - Mock", "tcWeth"));
        // TODO: Change to deployed wstEth address once composable stable deployed.
        wstEth = IERC20(new ERC20Mock("Mock wstEth", "mWstEth"));

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

        // Sort arrays.  Balancer requiers pool tokens in numerical order.
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
        address pool = IBalancerMetaStableFactory(BALANCER_METASTABLE_FACTORY_GOERLI).create(
            name, symbol, tokens, amplification, rateProviders, rateDurations, swapFeePercentage, oracleEnabled, owner
        );

        console.log("Pool: ", pool);
    }
}
