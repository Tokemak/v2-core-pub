// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";

import { BaseScript } from "../BaseScript.sol";
import { Systems } from "../utils/Constants.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerMetaStablePool } from "src/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BalancerMetaStableGoerliLiquidity is BaseScript {
    address public owner;

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);

        owner = vm.addr(vm.envUint(constants.privateKeyEnvVar));
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));

        console.log("Owner: ", owner);

        // Create pool.
        IBalancerMetaStablePool pool = IBalancerMetaStablePool(constants.pools.balMetaWethWsteth);

        bytes32 poolId = pool.getPoolId();
        (IERC20[] memory addrs,,) = IBalancerVault(constants.ext.balancerVault).getPoolTokens(poolId);

        uint256[] memory amounts = new uint256[](2);
        uint256[] memory userAmounts = new uint256[](2);
        address[] memory addresses = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            userAmounts[i] = 1e18;
            IERC20(address(addrs[i])).approve(constants.ext.balancerVault, 1000e18);
            addresses[i] = address(addrs[i]);
            amounts[i] = type(uint256).max;
        }

        IBalancerVault(constants.ext.balancerVault).joinPool{ value: 0 }(
            poolId,
            owner,
            owner,
            IBalancerVault.JoinPoolRequest(
                addresses,
                amounts,
                abi.encode(0, userAmounts),
                false // Don't use internal balances
            )
        );

        vm.stopBroadcast();
    }
}
