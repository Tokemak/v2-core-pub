// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";
import { AutopoolMainRewarder } from "src/rewarders/AutopoolMainRewarder.sol";

contract AutopoolFeesAndThresholds is Script {
    address public constant FEE_SINK = 0x4C0169B48c5A22503F1C3B871b921d55024A5939;
    address public constant TREASURY = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;

    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        // Set Autopool Fee Settings
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_FEE_UPDATER, owner);
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_PERIODIC_FEE_UPDATER, owner);

        // Set users who can add rewards to Autopool Rewarders
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_REWARD_MANAGER, owner);

        // Set idle thresholds on the Strategy
        constants.sys.accessController.grantRole(Roles.AUTO_POOL_MANAGER, owner);

        setValues(AutopoolETH(0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56));
        setValues(AutopoolETH(0xE800e3760FC20aA98c5df6A9816147f190455AF3));
        setValues(AutopoolETH(0x6dC3ce9C57b20131347FDc9089D740DAf6eB34c5));

        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_FEE_UPDATER, owner);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_PERIODIC_FEE_UPDATER, owner);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_REWARD_MANAGER, owner);
        constants.sys.accessController.revokeRole(Roles.AUTO_POOL_MANAGER, owner);
    }

    function setValues(AutopoolETH autopool) private {
        autopool.setFeeSink(FEE_SINK);
        autopool.setPeriodicFeeSink(FEE_SINK);

        autopool.setStreamingFeeBps(2000);
        autopool.setPeriodicFeeBps(85);

        AutopoolETHStrategy(address(autopool.autoPoolStrategy())).setIdleThresholds(0.0025e18, 0.005e18);

        AutopoolMainRewarder(address(autopool.rewarder())).addToWhitelist(TREASURY);
    }
}
