// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { BalancerLPMetaStableEthOracle } from "src/oracles/providers/BalancerLPMetaStableEthOracle.sol";
import { BAL_VAULT, RETH_MAINNET, WETH_MAINNET, RETH_WETH_BAL_POOL } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase

contract BalancerLPMetaStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPMetaStableEthOracle private oracle;

    event ReceivedPrice();

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_761_811);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPMetaStableEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }

    function testGetTotalSupply() public {
        uint256 totalSupply = oracle.getTotalSupply(RETH_WETH_BAL_POOL);

        assertEq(totalSupply, 18_835_128_225_380_167_044_171);
    }

    function testGetPoolTokens() public {
        (IERC20[] memory tokens, uint256[] memory balances) = oracle.getPoolTokens(RETH_WETH_BAL_POOL);

        assertEq(tokens.length, 2);
        assertEq(balances.length, 2);
        assertEq(address(tokens[0]), RETH_MAINNET);
        assertEq(address(tokens[1]), WETH_MAINNET);

        assertEq(balances[0], 8_808_766_373_866_645_553_286);
        assertEq(balances[1], 9_717_829_756_197_863_242_376);
    }
}
