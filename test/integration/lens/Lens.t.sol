// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Lens } from "src/lens/Lens.sol";
import { Roles } from "src/libs/Roles.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

// solhint-disable func-name-mixedcase,max-states-count,state-visibility,max-line-length

contract LensInt is Test {
    address public constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    Lens internal _lens;

    function _setUp(uint256 blockNumber) internal {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
        vm.selectFork(forkId);

        _lens = new Lens(ISystemRegistry(SYSTEM_REGISTRY));
    }

    function _findIndexOfPool(Lens.AutoPool[] memory pools, address toFind) internal returns (uint256) {
        uint256 ix = 0;
        bool found = false;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].poolAddress == toFind) {
                ix = i;
                found = true;
                break;
            }
        }

        assertEq(found, true, "poolFound");

        return ix;
    }

    function _findIndexOfDestination(
        Lens.AutoPools memory data,
        uint256 autoPoolIx,
        address toFind
    ) internal returns (uint256) {
        uint256 ix = 0;
        bool found = false;
        for (uint256 i = 0; i < data.destinations[autoPoolIx].length; i++) {
            if (data.destinations[autoPoolIx][i].vaultAddress == toFind) {
                ix = i;
                found = true;
                break;
            }
        }

        assertEq(found, true, "vaultFound");

        return ix;
    }
}

contract LensIntTest1 is LensInt {
    function setUp() public {
        _setUp(19_322_937);
    }

    function test_ReturnsVaults() public {
        // Should only have one deployed at this block

        Lens.AutoPool[] memory vaults = _lens.getPools();

        assertEq(vaults.length, 1, "len");
        assertEq(vaults[0].poolAddress, 0xA43a16d818Fea4Ad0Fb9356D33904251d726079b, "addr");
    }
}

contract LensIntTest2 is LensInt {
    function setUp() public {
        _setUp(19_322_937);
    }

    function test_ReturnsDestinations() external {
        Lens.AutoPools memory retValues = _lens.getPoolsAndDestinations();

        assertEq(retValues.autoPools.length, 1, "vaultLen");
        assertEq(retValues.autoPools[0].poolAddress, 0xA43a16d818Fea4Ad0Fb9356D33904251d726079b, "autoPoolAddr");

        assertEq(retValues.destinations[0].length, 2, "destLen");
        assertEq(
            retValues.destinations[0][0].vaultAddress, 0x1FDc5fb45F18E226F6380b1F1CA2C5cC7679Dd57, "vault0Dest0Address"
        );
        assertEq(
            retValues.destinations[0][1].vaultAddress, 0xFCe39291f1FDf890f8c17a9E0880a4726E78719B, "vault0Dest1Address"
        );

        assertTrue(retValues.destinations[0][0].statsSafeLPTotalSupply > 0, "vault0Dest0SafeTotalSupply");
        assertTrue(retValues.destinations[0][1].statsSafeLPTotalSupply > 0, "vault0Dest1SafeTotalSupply");

        assertTrue(retValues.destinations[0][0].actualLPTotalSupply > 0, "vault0Dest0ActualTotalSupply");
        assertTrue(retValues.destinations[0][1].actualLPTotalSupply > 0, "vault0Dest1ActualTotalSupply");

        assertEq(retValues.destinations[0][0].exchangeName, "curve", "vault0Dest0Exchange");
        assertEq(retValues.destinations[0][1].exchangeName, "curve", "vault0Dest1Exchange");

        assertEq(
            retValues.destinations[0][0].underlyingTokens[0].tokenAddress,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            "v0d0UnderlyingTokens0Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[0][0].underlyingTokenSymbols[0].symbol)),
            keccak256(abi.encode("WETH")),
            "v0d0UnderlyingTokens0Symbol"
        );
        assertEq(
            retValues.destinations[0][0].underlyingTokens[1].tokenAddress,
            0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            "v0d0UnderlyingTokens1Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[0][0].underlyingTokenSymbols[1].symbol)),
            keccak256(abi.encode("stETH")),
            "v0d0UnderlyingTokens1Symbol"
        );
    }
}

contract LensIntTest3 is LensInt {
    function setUp() public {
        _setUp(19_562_908);
    }

    function test_ReturnsUpdatedNavPerShare() public {
        // Have deployed the vault 4 time and the vault we're testing has had a debt reporting and claimed
        // rewards so has an increased nav/share

        Lens.AutoPool[] memory vaults = _lens.getPools();

        assertEq(vaults.length, 4, "len");

        uint256 ix = _findIndexOfPool(vaults, 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6);
        assertEq(vaults[ix].poolAddress, 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6, "addr");
        assertEq(vaults[ix].navPerShare, 1.00159598048077477e18, "navShare");
    }
}

contract LensIntTest4 is LensInt {
    function setUp() public {
        _setUp(19_543_980);
    }

    // function test_ReturnsVaultData() external {
    //     address autoPool = 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6;
    //     address admin = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;

    //     uint256 streamingFee = 9;
    //     uint256 periodicFee = 10;

    //     vm.startPrank(admin);
    //     LMPVault(autoPool).setStreamingFeeBps(streamingFee);
    //     LMPVault(autoPool).setPeriodicFeeBps(periodicFee);
    //     LMPVault(autoPool).setRebalanceFeeHighWaterMarkEnabled(true);
    //     LMPVault(autoPool).shutdown(ILMPVault.VaultShutdownStatus.Exploit);
    //     vm.stopPrank();

    //     Lens.AutoPool[] memory autoPools = _lens.getPools();
    //     uint256 ix = _findIndexOfPool(autoPools, autoPool);
    // }

    function test_ReturnsDestinationsWhenPricingIsStale() external {
        Lens.AutoPools memory data = _lens.getPoolsAndDestinations();
        uint256 ix = _findIndexOfPool(data.autoPools, 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6);

        bool someDestStatsIncomplete = false;
        for (uint256 d = 0; d < data.destinations[ix].length; d++) {
            if (data.destinations[ix][d].statsIncomplete) {
                someDestStatsIncomplete = true;
            }
        }

        assertEq(someDestStatsIncomplete, true, "destStatsIncomplete");
    }

    function test_ReturnsDestinationsQueuedForRemoval() external {
        // We removed cbETH/ETH earlier this day

        Lens.AutoPools memory data = _lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6);
        uint256 dix = _findIndexOfDestination(data, pix, 0x258Ef53417F3ce45A993b8aD777b87712322Cc7B);

        assertEq(data.destinations[pix].length, 4, "destLen");
        assertEq(data.destinations[pix][dix].lpTokenAddress, 0x5b6C539b224014A09B3388e51CaAA8e354c959C8, "lp");
    }
}

contract LensIntTest5 is LensInt {
    function setUp() public {
        _setUp(19_543_980);
    }

    function test_ReturnsVaultData() external {
        address autoPool = 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6;
        address admin = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;

        // TODO: Test the fee when we deploy a new version of the pool
        // uint256 streamingFee = 9;
        // uint256 periodicFee = 10;

        AccessController access = AccessController(address(ISystemRegistry(SYSTEM_REGISTRY).accessController()));

        vm.startPrank(admin);
        access.grantRole(Roles.LMP_VAULT_FEE_UPDATER, admin);
        access.grantRole(Roles.LMP_VAULT_PERIODIC_FEE_UPDATER, admin);
        access.grantRole(Roles.AUTO_POOL_MANAGER, admin);

        // LMPVault(autoPool).setStreamingFeeBps(streamingFee);
        // LMPVault(autoPool).setPeriodicFeeBps(periodicFee);
        LMPVault(autoPool).setRebalanceFeeHighWaterMarkEnabled(true);
        LMPVault(autoPool).shutdown(ILMPVault.VaultShutdownStatus.Exploit);
        vm.stopPrank();

        Lens.AutoPool[] memory autoPools = _lens.getPools();
        Lens.AutoPool memory pool = autoPools[_findIndexOfPool(autoPools, autoPool)];

        assertEq(pool.poolAddress, autoPool, "poolAddress");
        // Accidentally had a space in the deploy script for the name at this time
        assertEq(pool.name, "Tokemak Guarded autoETH ", "name");
        assertEq(pool.symbol, "autoETH_guarded", "symbol");
        assertEq(pool.vaultType, 0xde6f3096d4f66344ff788320cd544f72ff6f5662e94f10e931a2dc34104866b7, "vaultType");
        assertEq(pool.baseAsset, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "baseAsset");
        // assertEq(pool.streamingFeeBps, streamingFee, "streamingFeeBps");
        // assertEq(pool.periodicFeeBps, periodicFee, "periodicFeeBps");
        // assertEq(pool.feeHighMarkEnabled, true, "feeHighMarkEnabled");
        // assertEq(pool.feeSettingsIncomplete, false, "feeSettingsIncomplete");
        assertEq(pool.feeSettingsIncomplete, true, "feeSettingsIncomplete");
        assertEq(pool.isShutdown, true, "isShutdown");
        assertEq(uint256(pool.shutdownStatus), uint256(ILMPVault.VaultShutdownStatus.Exploit), "shutdownStatus");
        assertEq(pool.rewarder, 0xA5e7672f88C4a8995F191d7B7e4725cD3a6d245B, "rewarder");
        assertEq(pool.strategy, 0xb9058eE7866458cDd6f78b12bC3B401C8D284d8E, "strategy");
        assertEq(pool.totalSupply, 26_235_717_700_643_078_755, "totalSupply");
        assertEq(pool.totalAssets, 26_277_589_393_992_422_242, "totalAssets");
        assertEq(pool.totalIdle, 0, "totalIdle");
        assertEq(pool.totalDebt, 26_277_589_393_992_422_242, "totalDebt");
        assertEq(pool.navPerShare, 1_001_595_980_480_774_770, "navPerShare");
    }
}

contract LensIntTest6 is LensInt {
    function setUp() public {
        _setUp(19_563_424);
    }

    function test_ReturnsDestinationVaultData() external {
        address autoPool = 0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6;
        // stETH/ETH ng
        address destVault = 0xba1a495630a948f0942081924a5682f4f55E3e82;
        address admin = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;

        vm.startPrank(admin);
        IDestinationVault(destVault).shutdown(IDestinationVault.VaultShutdownStatus.Exploit);
        vm.stopPrank();

        Lens.AutoPools memory data = _lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, autoPool);
        uint256 dix = _findIndexOfDestination(data, pix, destVault);
        Lens.DestinationVault memory dv = data.destinations[pix][dix];

        assertEq(dv.vaultAddress, destVault, "vaultAddress");
        assertEq(dv.exchangeName, "curve", "exchangeName");
        assertEq(dv.totalSupply, 25_692_933_029_349_164_507, "totalSupply");
        assertEq(dv.lastSnapshotTimestamp, 1_711_989_395, "lastSnapshotTimestamp");
        assertEq(dv.feeApr, 7_775_774_073_658_430, "feeApr");
        assertEq(dv.lastDebtReportTime, 1_711_739_123, "lastDebtReportTime");
        assertEq(dv.minDebtValue, 26.273792128529177534e18, "minDebtValue");
        assertEq(dv.maxDebtValue, 26.28138665945566695e18, "maxDebtValue");
        assertEq(dv.debtValueHeldByVault, 26_277_589_393_992_422_242, "debtValueHeldByVault");
        assertEq(dv.queuedForRemoval, false, "queuedForRemoval");
        assertEq(dv.isShutdown, true, "isShutdown");
        assertEq(uint256(dv.shutdownStatus), uint256(IDestinationVault.VaultShutdownStatus.Exploit), "shutdownStats");
        assertEq(dv.statsIncomplete, false, "statsIncomplete");
        assertEq(dv.autoPoolOwnsShares, 25_692_933_029_349_164_507, "vaultOwnsShares");
        assertEq(dv.actualLPTotalSupply, 29_184_961_658_684_302_331_099, "actualLPTotalSupply");
        assertEq(dv.dexPool, 0x21E27a5E5513D6e65C4f830167390997aA84843a, "dexPool");
        assertEq(dv.lpTokenAddress, 0x21E27a5E5513D6e65C4f830167390997aA84843a, "lpTokenAddress");
        assertEq(dv.lpTokenSymbol, "stETH-ng-f", "lpTokenSymbol");
        assertEq(dv.lpTokenName, "Curve.fi Factory Pool: stETH-ng", "lpTokenName");
        assertEq(dv.statsSafeLPTotalSupply, 28_194_429_527_111_520_327_141, "statsSafeLPTotalSupply");
        assertEq(dv.statsIncentiveCredits, 40, "statsIncentiveCredits");
        assertEq(dv.reservesInEth.length, 2, "reservesInEthLen");
        assertEq(dv.reservesInEth[0], 4_753_387_733_997_902_472_990, "reservesInEth0");
        assertEq(dv.reservesInEth[1], 25_103_131_256_061_390_868_175, "reservesInEth1");
        assertEq(dv.statsPeriodFinishForRewards.length, 4, "statsPeriodFinishForRewardsLen");
        assertEq(dv.statsPeriodFinishForRewards[0], 1_712_229_683, "statsPeriodFinishForRewards[0]");
        assertEq(dv.statsPeriodFinishForRewards[1], 1_712_229_683, "statsPeriodFinishForRewards[1]");
        assertEq(dv.statsPeriodFinishForRewards[2], 0, "statsPeriodFinishForRewards[2]");
        assertEq(dv.statsPeriodFinishForRewards[3], 0, "statsPeriodFinishForRewards[3]");
        assertEq(dv.statsAnnualizedRewardAmounts.length, 4, "statsAnnualizedRewardAmountsLen");
        assertEq(
            dv.statsAnnualizedRewardAmounts[0], 2_110_759_800_123_025_661_760_000, "statsAnnualizedRewardAmounts[0]"
        );
        assertEq(dv.statsAnnualizedRewardAmounts[1], 10_553_799_000_615_128_308_800, "statsAnnualizedRewardAmounts[1]");
        assertEq(dv.statsAnnualizedRewardAmounts[2], 0, "statsAnnualizedRewardAmounts[2]");
        assertEq(dv.statsAnnualizedRewardAmounts[3], 0, "statsAnnualizedRewardAmounts[3]");
        assertEq(dv.rewardsTokens.length, 4, "rewardTokenAddressLen");
        assertEq(dv.rewardsTokens[0].tokenAddress, 0xD533a949740bb3306d119CC777fa900bA034cd52, "rewardTokenAddress0");
        assertEq(dv.rewardsTokens[1].tokenAddress, 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "rewardTokenAddress1");
        assertEq(dv.rewardsTokens[2].tokenAddress, 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "rewardTokenAddress2");
        assertEq(dv.rewardsTokens[3].tokenAddress, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, "rewardTokenAddress3");
        assertEq(dv.underlyingTokens.length, 2, "underlyingTokenAddressLen");
        assertEq(
            dv.underlyingTokens[0].tokenAddress, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "underlyingTokenAddress[0]"
        );
        assertEq(
            dv.underlyingTokens[1].tokenAddress, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, "underlyingTokenAddress[1]"
        );
        assertEq(dv.underlyingTokenSymbols.length, 2, "underlyingTokenSymbolsLen");
        assertEq(dv.underlyingTokenSymbols[0].symbol, "WETH", "underlyingTokenSymbols[0]");
        assertEq(dv.underlyingTokenSymbols[1].symbol, "stETH", "underlyingTokenSymbols[1]");
        assertEq(dv.underlyingTokenValueHeld.length, 2, "underlyingTokenValueHeldLen");
        assertEq(dv.underlyingTokenValueHeld[0].valueHeldInEth, 4.184637079206072398e18, "underlyingTokenValueHeld[0]");
        assertEq(dv.underlyingTokenValueHeld[1].valueHeldInEth, 22.099500343082628172e18, "underlyingTokenValueHeld[0]");
        assertEq(dv.lstStatsData.length, 2, "lstStatsDataLen");
    }
}
