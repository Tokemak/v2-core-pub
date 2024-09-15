// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console,max-line-length

import { Script } from "forge-std/Script.sol";
import { Systems } from "script/utils/Constants.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";

import { Roles } from "src/libs/Roles.sol";

import { Systems, Constants } from "../utils/Constants.sol";
import { Oracle } from "script/core/Oracle.sol";

// solhint-disable state-visibility,no-console

contract OracleSetup is Script, Oracle {
    function run() external {
        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        constants.sys.accessController.grantRole(Roles.ORACLE_MANAGER, owner);

        _configureChainlinkLookups(constants);

        _configureRedstoneLookups(constants);

        _configureCustomSetLookups(constants);

        _configureUniqueLookups(constants);

        constants.sys.accessController.revokeRole(Roles.ORACLE_MANAGER, owner);

        vm.stopBroadcast();
    }

    function _configureUniqueLookups(Constants.Values memory constants) internal {
        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.wstEth, constants.tokens.wstEth, true);
        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.eEth, constants.tokens.eEth, true);
        _registerMapping(constants.sys.rootPriceOracle, constants.sys.subOracles.ethPegged, constants.tokens.weth, true);
        _registerMapping(
            constants.sys.rootPriceOracle, constants.sys.subOracles.ethPegged, constants.tokens.curveEth, true
        );

        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.weth, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.wstEth, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.eEth, 200);
    }

    function _configureChainlinkLookups(Constants.Values memory constants) internal {
        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.usdc,
                feedAddress: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.cbEth,
                feedAddress: 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.rEth,
                feedAddress: 0x536218f9E9Eb48863970252233c8F271f554C2d0,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.stEth,
                feedAddress: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.crv,
                feedAddress: 0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.cvx,
                feedAddress: 0xC9CbF687f43176B302F03f5e58470b77D07c61c6,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: ETH_IN_USD,
                feedAddress: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
                denomination: BaseOracleDenominations.Denomination.USD,
                heartbeat: 2 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.ldo,
                feedAddress: 0x4e844125952D32AcdF339BE976c98E22F6F318dB,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.rpl,
                feedAddress: 0x4E155eD98aFE9034b7A5962f6C84c86d869daA9d,
                denomination: BaseOracleDenominations.Denomination.USD,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.bal,
                feedAddress: 0xC1438AA3823A6Ba0C159CfA8D98dF5A994bA120b,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupChainlinkOracle(
            constants,
            ChainlinkOracleSetup({
                tokenAddress: constants.tokens.oEth,
                feedAddress: 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );
    }

    function _configureCustomSetLookups(Constants.Values memory constants) internal {
        address[] memory tokens = new address[](6);
        uint256[] memory maxAges = new uint256[](6);

        tokens[0] = constants.tokens.aura;
        maxAges[0] = 1 days;

        tokens[1] = constants.tokens.swise;
        maxAges[1] = 1 days;

        tokens[2] = constants.tokens.toke;
        maxAges[2] = 1 days;

        tokens[3] = constants.tokens.pxEth;
        maxAges[3] = 1 days;

        tokens[4] = constants.tokens.dinero;
        maxAges[4] = 1 days;

        tokens[5] = constants.tokens.frxEth;
        maxAges[5] = 1 days;

        constants.sys.subOracles.customSet.registerTokens(tokens, maxAges);
        for (uint256 i = 0; i < tokens.length; ++i) {
            constants.sys.rootPriceOracle.registerMapping(tokens[i], constants.sys.subOracles.customSet);
        }

        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.frxEth, 200);
        constants.sys.rootPriceOracle.setSafeSpotPriceThreshold(constants.tokens.pxEth, 200);
    }

    function _configureRedstoneLookups(Constants.Values memory constants) internal {
        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.rswEth,
                feedAddress: 0x3A236F67Fce401D87D7215695235e201966576E4,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.ezEth,
                feedAddress: 0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 12 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.rsEth,
                feedAddress: 0xA736eAe8805dDeFFba40cAB8c99bCB309dEaBd9B,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.ethX,
                feedAddress: 0xc799194cAa24E2874Efa89b4Bf5c92a530B047FF,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.weEth,
                feedAddress: 0x8751F736E94F6CD167e8C5B97E245680FbD9CC36,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.osEth,
                feedAddress: 0x66ac817f997Efd114EDFcccdce99F3268557B32C,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.swEth,
                feedAddress: 0x061bB36F8b67bB922937C102092498dcF4619F86,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 6 hours,
                safePriceThreshold: 200
            })
        );

        _setupRedstoneOracle(
            constants,
            RedstoneOracleSetup({
                tokenAddress: constants.tokens.apxEth,
                feedAddress: 0x19219BC90F48DeE4d5cF202E09c438FAacFd8Bea,
                denomination: BaseOracleDenominations.Denomination.ETH,
                heartbeat: 24 hours,
                safePriceThreshold: 200
            })
        );
    }
}
