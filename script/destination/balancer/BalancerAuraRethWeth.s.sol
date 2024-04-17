// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { BalancerAuraDestinationVaultBase } from "script/destination/balancer/BalancerAuraDestinationVaultBase.s.sol";

contract BalancerAuraRethWeth is BalancerAuraDestinationVaultBase {
    function _getData()
        internal
        view
        override
        returns (string memory, address, BalancerAuraDestinationVault.InitParams memory)
    {
        address calculator = 0x1D1352D930287C993b2ace1Afb463eC4f5dd0Cc8;
        return (
            "balancer-aura",
            calculator,
            BalancerAuraDestinationVault.InitParams({
                balancerPool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
                auraStaking: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
                auraBooster: constants.ext.auraBooster,
                auraPoolId: 109
            })
        );
    }
}
