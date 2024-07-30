// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// // solhint-disable no-console,max-states-count,max-line-length

// import { Stats } from "src/stats/Stats.sol";
// import { Roles } from "src/libs/Roles.sol";
// import { Script } from "forge-std/Script.sol";
// import { console } from "forge-std/console.sol";
// import { Systems, Constants } from "../utils/Constants.sol";
// import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
// import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
// import { ProxyLSTCalculator } from "src/stats/calculators/ProxyLSTCalculator.sol";
// import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
// import { AerodromeStakingDexCalculator } from "src/stats/calculators/AerodromeStakingDexCalculator.sol";
// import { AerodromStakingIncentiveCalculator } from "src/stats/calculators/AerodromeStakingIncentiveCalculator.sol";
// import { Calculators } from "script/core/Calculators.sol";

// contract Aero is Script, Calculators {
//     Constants.Values public constants;

//     // Incentive Template Ids
//     bytes32 internal aeroTemplateId = keccak256("incentive-aero");

//     // DEX Template Ids
//     bytes32 internal balCompTemplateId = keccak256("dex-aero");

//     function run() external {
//         constants = Constants.get(Systems.LST_GEN1_BASE);

//         vm.startBroadcast();

//         (, address owner,) = vm.readCallers();

//         constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
//         deployTemplates();
//         constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

//         constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
//         deployAeroPools();
//         constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

//         vm.stopBroadcast();
//     }

//     function deployAeroPools() private {
//         _setupAeroDexCalculator(constants, AeroDexSetup({ name: "" }));
//     }

//     function deployTemplates() private {
//         AerodromeStakingDexCalculator aeroDexTemplate = new
// AerodromeStakingDexCalculator(constants.sys.systemRegistry);

//         console.log("Aero DEX Template", address(aeroDexTemplate));

//         AerodromStakingIncentiveCalculator aeroIncentive =
//             new AerodromStakingIncentiveCalculator(constants.sys.systemRegistry);

//         console.log("Aero Incentive Template", address(aeroIncentive));
//     }
// }
