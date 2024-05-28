// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { BaseStatsCalculator } from "src/stats/calculators/base/BaseStatsCalculator.sol";
import { MaverickDestinationVault } from "src/vault/MaverickDestinationVault.sol";
import { MaverickCalculator } from "src/stats/calculators/MaverickCalculator.sol";
import { MaverickDexCalculator } from "src/stats/calculators/MaverickDexCalculator.sol";
import { MaverickFeeAprOracle } from "src/oracles/providers/MaverickFeeAprOracle.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

contract Maverick is Script {
    uint256 public saltIx;
    Constants.Values public constants;

    bytes32 public mavDexCalculatorTemplateId = keccak256("dex-maverick");
    bytes32 public maverickIncentiveTemplateId = keccak256("incentive-maverick");

    address public feeAprOracle;

    struct MaverickSetup {
        string name;
        address mavRouter;
        address mavBoostedPosition;
        address mavRewarder;
        address mavPool;
    }

    MaverickCalculator public maverickIncentiveTemplate;
    MaverickDexCalculator public maverickDexCalcTemplate;

    IStatsCalculator public mavWstEthDexCalc;
    IStatsCalculator public mavWstEthIncentiveCalc;
    IStatsCalculator public mavEthSwEthCalc;
    IStatsCalculator public mavEthSwEthIncentiveCalc;

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);
        deployCalculatorTemplates();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, owner);

        feeAprOracle = address(new MaverickFeeAprOracle(constants.sys.systemRegistry));
        console.log("Maverick Fee Apr Oracle: ", feeAprOracle);

        constants.sys.accessController.grantRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);
        deployCalculators();
        constants.sys.accessController.revokeRole(Roles.STATS_CALC_FACTORY_MANAGER, owner);

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);
        setupDestinations();
        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function deployCalculatorTemplates() internal {
        maverickIncentiveTemplate = new MaverickCalculator(constants.sys.systemRegistry);
        registerAndOutput("Maverick Incentive Template", maverickIncentiveTemplate, maverickIncentiveTemplateId);

        maverickDexCalcTemplate = new MaverickDexCalculator(constants.sys.systemRegistry);
        registerAndOutput("Maverick Dex Template", maverickDexCalcTemplate, mavDexCalculatorTemplateId);
    }

    function deployCalculators() internal {
        bytes32[] memory e = new bytes32[](2);

        e[0] = 0xbbbb8b0b04cae7b304cb89a0a24c999f3985e8a4d0a468f74e709863fdc71136; // wstETH
        e[1] = Stats.NOOP_APR_ID;
        mavWstEthDexCalc = IStatsCalculator(
            _setupMaverickDexCalculator(
                "Maverick wstETH/ETH Pool #110",
                mavDexCalculatorTemplateId,
                e,
                0x0eB1C92f9f5EC9D817968AfDdB4B46c564cdeDBe,
                0x8dA58a7E98A3D7a8c2195374dBFFAd1D21d4b811
            )
        );

        mavWstEthIncentiveCalc = IStatsCalculator(
            _setupMavIncentiveCalculator(
                "Maverick wstETH/ETH Pool #110 Incentives",
                mavWstEthDexCalc,
                0x19206847B826427919ABeF3dA023A80a05415548,
                0x8dA58a7E98A3D7a8c2195374dBFFAd1D21d4b811
            )
        );

        e[0] = Stats.NOOP_APR_ID;
        e[1] = 0xdd747770928da8ec36d35059aa8102da8c4ff51476ec483a3f8942a368938b1f;
        mavEthSwEthCalc = IStatsCalculator(
            _setupMaverickDexCalculator(
                "Maverick ETH/swETH Pool #42",
                mavDexCalculatorTemplateId,
                e,
                0x0CE176E1b11A8f88a4Ba2535De80E81F88592bad,
                0xA2306Ce8e7B747BdaB363E0e954fcaaCc6A8Cc15
            )
        );

        mavEthSwEthIncentiveCalc = IStatsCalculator(
            _setupMavIncentiveCalculator(
                "Maverick ETH/swETH Pool #42 Incentives",
                mavEthSwEthCalc,
                0x7277A72223707aD9e1c9E1a2123317e5EfD66C4E,
                0xA2306Ce8e7B747BdaB363E0e954fcaaCc6A8Cc15
            )
        );
    }

    function setupDestinations() internal {
        setupMaverickDestinations();
    }

    function setupMaverickDestinations() internal {
        setupMaverickDestinationVault(
            MaverickSetup({
                name: "Mav wstETH/ETH #110",
                mavRouter: constants.ext.mavRouter,
                mavBoostedPosition: 0x8dA58a7E98A3D7a8c2195374dBFFAd1D21d4b811,
                mavRewarder: 0x19206847B826427919ABeF3dA023A80a05415548,
                mavPool: 0x0eB1C92f9f5EC9D817968AfDdB4B46c564cdeDBe
            })
        );

        setupMaverickDestinationVault(
            MaverickSetup({
                name: "Maverick ETH/swETH Pool #42",
                mavRouter: constants.ext.mavRouter,
                mavBoostedPosition: 0xA2306Ce8e7B747BdaB363E0e954fcaaCc6A8Cc15,
                mavRewarder: 0x7277A72223707aD9e1c9E1a2123317e5EfD66C4E,
                mavPool: 0x0CE176E1b11A8f88a4Ba2535De80E81F88592bad
            })
        );
    }

    function _setupMaverickDexCalculator(
        string memory name,
        bytes32 aprTemplateId,
        bytes32[] memory dependentAprIds,
        address pool,
        address boostedPosition
    ) internal returns (address) {
        MaverickDexCalculator.InitData memory initData = MaverickDexCalculator.InitData({
            pool: pool,
            boostedPosition: boostedPosition,
            dexReserveAlpha: 33e16,
            feeAprOracle: feeAprOracle
        });

        bytes memory encodedInitData = abi.encode(initData);

        address addr = constants.sys.statsCalcFactory.create(aprTemplateId, dependentAprIds, encodedInitData);

        outputDexCalculator(name, addr);

        return addr;
    }

    function setupMaverickDestinationVault(MaverickSetup memory args) internal {
        MaverickDestinationVault.InitParams memory initParams = MaverickDestinationVault.InitParams({
            maverickRouter: args.mavRouter,
            maverickBoostedPosition: args.mavBoostedPosition,
            maverickRewarder: args.mavRewarder,
            maverickPool: args.mavPool
        });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                "mav-v1",
                constants.tokens.weth,
                args.mavBoostedPosition,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(keccak256(abi.encode("incentive", args.mavRewarder)))
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Maverick ", args.name, " Dest Vault: "), address(newVault));
    }

    function _setupMavIncentiveCalculator(
        string memory name,
        IStatsCalculator poolCalculator,
        address boostedRewarder,
        address boostedPosition
    ) internal returns (address) {
        MaverickCalculator.InitData memory initData = MaverickCalculator.InitData({
            underlyerStats: address(poolCalculator),
            boostedRewarder: boostedRewarder,
            boostedPosition: boostedPosition
        });

        bytes memory encodedInitData = abi.encode(initData);

        address addr =
            constants.sys.statsCalcFactory.create(maverickIncentiveTemplateId, new bytes32[](0), encodedInitData);

        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " Incentive Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("-----------------");
        vm.startBroadcast();

        return addr;
    }

    function registerAndOutput(string memory name, BaseStatsCalculator template, bytes32 id) private {
        constants.sys.statsCalcFactory.registerTemplate(id, address(template));
        console.log("-------------------------");
        console.log(string.concat(name, ": "), address(template));
        console.logBytes32(id);
        console.log("-------------------------");
    }

    function outputDexCalculator(string memory name, address addr) private {
        vm.stopBroadcast();
        console.log("-----------------");
        console.log(string.concat(name, " DEX Calculator address: "), addr);
        console.log(
            string.concat(name, " Last Snapshot Timestamp: "), IDexLSTStats(addr).current().lastSnapshotTimestamp
        );
        console.log("-----------------");
        vm.startBroadcast();
    }
}
