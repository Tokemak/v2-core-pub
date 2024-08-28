// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Lens } from "src/lens/Lens.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";

// solhint-disable func-name-mixedcase,max-states-count,state-visibility,max-line-length
// solhint-disable avoid-low-level-calls,gas-custom-errors,custom-errors

contract LensInt is Test {
    address public constant SYSTEM_REGISTRY = 0xB20193f43C9a7184F3cbeD9bAD59154da01488b4;
    address public constant SYSTEM_REGISTRY_SEPOLIA = 0x25F603C1a0Ce130c7F25321A7116379d3c270c23;

    Lens internal lens;

    AccessController internal access;

    IAutopoolRegistry internal autoPoolRegistry;

    function _setUp(uint256 _forkId, address _systemRegistry) internal {
        vm.selectFork(_forkId);

        ISystemRegistry systemRegistry = ISystemRegistry(_systemRegistry);

        lens = new Lens(systemRegistry);

        autoPoolRegistry = IAutopoolRegistry(systemRegistry.autoPoolRegistry());

        access = AccessController(address(systemRegistry.accessController()));
    }

    function _findIndexOfPool(Lens.Autopool[] memory pools, address toFind) internal returns (uint256) {
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
        Lens.Autopools memory data,
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
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsVaults() public {
        Lens.Autopool[] memory vaults = lens.getPools();

        assertEq(vaults.length, 4, "len");
        assertEq(vaults[0].poolAddress, 0x94a2Fa8FD1864bE4f675D7617A400e87123b56AA, "addr0");
        assertEq(vaults[1].poolAddress, 0xf0eF0dFCd5A39AFAFb51Ca0C0024A49D67cD8c68, "addr1");
        assertEq(vaults[2].poolAddress, 0x49C4719EaCc746b87703F964F09C22751F397BA0, "addr2");
        assertEq(vaults[3].poolAddress, 0x72cf6d7C85FfD73F18a83989E7BA8C1c30211b73, "addr3");
    }
}

contract LensIntTest2 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsDestinations() external {
        Lens.Autopools memory retValues = lens.getPoolsAndDestinations();

        assertEq(retValues.autoPools.length, 4, "vaultLen");
        assertEq(retValues.autoPools[2].poolAddress, 0x49C4719EaCc746b87703F964F09C22751F397BA0, "autoPoolAddr");

        assertEq(retValues.destinations[2].length, 17, "destLen");
        assertEq(
            retValues.destinations[2][0].vaultAddress, 0x75FD0d0247fA088852417CD0F1bfa21D1d78aa14, "vault2Dest0Address"
        );
        assertEq(
            retValues.destinations[2][1].vaultAddress, 0xD43e6d2a8B983DDEf52eC50eF0E3159542fEF8ed, "vault2Dest1Address"
        );

        assertTrue(retValues.destinations[2][0].statsSafeLPTotalSupply == 0, "vault2Dest0SafeTotalSupply");
        assertTrue(retValues.destinations[2][1].statsSafeLPTotalSupply == 0, "vault2Dest1SafeTotalSupply");

        assertTrue(retValues.destinations[2][0].actualLPTotalSupply > 0, "vault2Dest0ActualTotalSupply");
        assertTrue(retValues.destinations[2][1].actualLPTotalSupply > 0, "vault2Dest1ActualTotalSupply");

        assertEq(retValues.destinations[2][0].exchangeName, "curve", "vault2Dest0Exchange");
        assertEq(retValues.destinations[2][1].exchangeName, "curve", "vault2Dest1Exchange");

        assertEq(
            retValues.destinations[2][0].underlyingTokens[0].tokenAddress,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            "v2d0UnderlyingTokens0Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[2][0].underlyingTokenSymbols[0].symbol)),
            keccak256(abi.encode("WETH")),
            "v2d0UnderlyingTokens0Symbol"
        );
        assertEq(
            retValues.destinations[2][0].underlyingTokens[1].tokenAddress,
            0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            "v2d0UnderlyingTokens1Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[2][0].underlyingTokenSymbols[1].symbol)),
            keccak256(abi.encode("stETH")),
            "v2d0UnderlyingTokens1Symbol"
        );
    }
}

contract LensIntTest3 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsUpdatedNavPerShare() public {
        // Have deployed the vault 4 time and the vault we're testing has had a debt reporting and claimed
        // rewards so has an increased nav/share

        Lens.Autopool[] memory vaults = lens.getPools();

        assertEq(vaults.length, 4, "len");

        uint256 ix = _findIndexOfPool(vaults, 0x94a2Fa8FD1864bE4f675D7617A400e87123b56AA);
        assertEq(vaults[ix].poolAddress, 0x94a2Fa8FD1864bE4f675D7617A400e87123b56AA, "addr");
        assertEq(vaults[ix].navPerShare, 1_000_000_000_000_000_000, "navShare");
    }
}

contract LensIntTest4 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsDestinationsWhenPricingIsStale() external {
        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 ix = _findIndexOfPool(data.autoPools, 0x49C4719EaCc746b87703F964F09C22751F397BA0);

        bool someDestStatsIncomplete = false;
        for (uint256 d = 0; d < data.destinations[ix].length; d++) {
            if (data.destinations[ix][d].statsIncomplete) {
                someDestStatsIncomplete = true;
            }
        }

        assertEq(someDestStatsIncomplete, true, "destStatsIncomplete");
    }

    function test_ReturnsDestinationsQueuedForRemoval() external {
        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, 0x49C4719EaCc746b87703F964F09C22751F397BA0);
        uint256 dix = _findIndexOfDestination(data, pix, 0x75FD0d0247fA088852417CD0F1bfa21D1d78aa14);

        assertEq(data.destinations[pix].length, 17, "destLen");
        assertEq(data.destinations[pix][dix].lpTokenAddress, 0x06325440D014e39736583c165C2963BA99fAf14E, "lp");
    }
}

contract LensIntTest5 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsVaultData() external {
        address autoPool = 0x49C4719EaCc746b87703F964F09C22751F397BA0;
        address admin = 0xb9535f36be0792f5A381249a3099B08e046a3cD8;

        uint256 streamingFee = 9;
        uint256 periodicFee = 10;

        vm.startPrank(admin);
        access.grantRole(Roles.AUTO_POOL_FEE_UPDATER, admin);
        access.grantRole(Roles.AUTO_POOL_PERIODIC_FEE_UPDATER, admin);
        access.grantRole(Roles.AUTO_POOL_MANAGER, admin);

        AutopoolETH(autoPool).setStreamingFeeBps(streamingFee);
        AutopoolETH(autoPool).setPeriodicFeeBps(periodicFee);
        AutopoolETH(autoPool).setRebalanceFeeHighWaterMarkEnabled(true);
        AutopoolETH(autoPool).shutdown(IAutopool.VaultShutdownStatus.Exploit);
        vm.stopPrank();

        Lens.Autopool[] memory autoPools = lens.getPools();
        Lens.Autopool memory pool = autoPools[_findIndexOfPool(autoPools, autoPool)];

        assertEq(pool.poolAddress, autoPool, "poolAddress");
        assertEq(pool.name, "Tokemak Guarded autoETH Gen2", "name");
        assertEq(pool.symbol, "autoETH_guarded_gen2", "symbol");
        assertEq(pool.vaultType, 0xde6f3096d4f66344ff788320cd544f72ff6f5662e94f10e931a2dc34104866b7, "vaultType");
        assertEq(pool.baseAsset, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "baseAsset");
        assertEq(pool.streamingFeeBps, streamingFee, "streamingFeeBps");
        assertEq(pool.periodicFeeBps, periodicFee, "periodicFeeBps");
        assertEq(pool.feeHighMarkEnabled, true, "feeHighMarkEnabled");
        assertEq(pool.feeSettingsIncomplete, true, "feeSettingsIncomplete");
        assertEq(pool.isShutdown, true, "isShutdown");
        assertEq(uint256(pool.shutdownStatus), uint256(IAutopool.VaultShutdownStatus.Exploit), "shutdownStatus");
        assertEq(pool.rewarder, 0x8D6556FBD44113A3D2d8fdd49EAF47e46aEfb9Be, "rewarder");
        assertEq(pool.strategy, 0x6D81BB06Cf70f05B93231875D2A2848d0a5bD9f8, "strategy");
        assertEq(pool.totalSupply, 35_551_434_621_716_291_439, "totalSupply");
        assertEq(pool.totalAssets, 35_956_287_834_164_246_024, "totalAssets");
        assertEq(pool.totalIdle, 240_932_931_955_089_917, "totalIdle");
        assertEq(pool.totalDebt, 35_715_354_902_209_156_107, "totalDebt");
        assertEq(pool.navPerShare, 1_011_387_816_462_423_528, "navPerShare");
    }
}

contract LensIntTest6 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_620_939);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    // TODO: update with another setup that has more data, specifically rewards
    function test_ReturnsDestinationVaultData() external {
        address autoPool = 0x49C4719EaCc746b87703F964F09C22751F397BA0;
        // Curve cbETH/ETH
        address destVault = 0x1A73e18B2a677940Cf5d5eb8bC244854Dc07d551;
        address admin = 0xb9535f36be0792f5A381249a3099B08e046a3cD8;

        vm.startPrank(admin);
        access.grantRole(Roles.DESTINATION_VAULT_MANAGER, admin);
        IDestinationVault(destVault).shutdown(IDestinationVault.VaultShutdownStatus.Exploit);
        vm.stopPrank();

        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, autoPool);
        uint256 dix = _findIndexOfDestination(data, pix, destVault);
        Lens.DestinationVault memory dv = data.destinations[pix][dix];

        assertEq(dv.vaultAddress, destVault, "vaultAddress");
        assertEq(dv.exchangeName, "curve", "exchangeName");
        assertEq(dv.totalSupply, 0, "totalSupply");
        assertEq(dv.lastSnapshotTimestamp, 0, "lastSnapshotTimestamp");
        assertEq(dv.feeApr, 0, "feeApr");
        assertEq(dv.lastDebtReportTime, 0, "lastDebtReportTime");
        assertEq(dv.minDebtValue, 0, "minDebtValue");
        assertEq(dv.maxDebtValue, 0, "maxDebtValue");
        assertEq(dv.debtValueHeldByVault, 0, "debtValueHeldByVault");
        assertEq(dv.queuedForRemoval, false, "queuedForRemoval");
        assertEq(dv.isShutdown, true, "isShutdown");
        assertEq(uint256(dv.shutdownStatus), uint256(IDestinationVault.VaultShutdownStatus.Exploit), "shutdownStats");
        assertEq(dv.statsIncomplete, true, "statsIncomplete");
        assertEq(dv.autoPoolOwnsShares, 0, "vaultOwnsShares");
        assertEq(dv.actualLPTotalSupply, 191_610_283_868_462_962_014, "actualLPTotalSupply");
        assertEq(dv.dexPool, 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A, "dexPool");
        assertEq(dv.lpTokenAddress, 0x5b6C539b224014A09B3388e51CaAA8e354c959C8, "lpTokenAddress");
        assertEq(dv.lpTokenSymbol, "cbETH/ETH-f", "lpTokenSymbol");
        assertEq(dv.lpTokenName, "Curve.fi Factory Crypto Pool: cbETH/ETH", "lpTokenName");
        assertEq(dv.statsSafeLPTotalSupply, 0, "statsSafeLPTotalSupply");
        assertEq(dv.statsIncentiveCredits, 0, "statsIncentiveCredits");
        assertEq(dv.reservesInEth.length, 0, "reservesInEthLen");
        // assertEq(dv.reservesInEth[0], 1e18, "reservesInEth0");
        // assertEq(dv.reservesInEth[1], 2e18, "reservesInEth1");
        assertEq(dv.statsPeriodFinishForRewards.length, 0, "statsPeriodFinishForRewardsLen");
        // assertEq(dv.statsPeriodFinishForRewards[0], 1_712_229_683, "statsPeriodFinishForRewards[0]");
        // assertEq(dv.statsPeriodFinishForRewards[1], 1_712_229_683, "statsPeriodFinishForRewards[1]");
        assertEq(dv.statsAnnualizedRewardAmounts.length, 0, "statsAnnualizedRewardAmountsLen");
        // assertEq(
        //     dv.statsAnnualizedRewardAmounts[0], 2_110_759_800_123_025_661_760_000, "statsAnnualizedRewardAmounts[0]"
        // );
        // assertEq(dv.statsAnnualizedRewardAmounts[1], 10_553_799_000_615_128_308_800,
        // "statsAnnualizedRewardAmounts[1]");
        assertEq(dv.rewardsTokens.length, 0, "rewardTokenAddressLen");
        // assertEq(dv.rewardsTokens[0].tokenAddress, 0xD533a949740bb3306d119CC777fa900bA034cd52,
        // "rewardTokenAddress0");
        // assertEq(dv.rewardsTokens[1].tokenAddress, 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
        // "rewardTokenAddress1");
        assertEq(dv.underlyingTokens.length, 2, "underlyingTokenAddressLen");
        assertEq(
            dv.underlyingTokens[0].tokenAddress, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "underlyingTokenAddress[0]"
        );
        assertEq(
            dv.underlyingTokens[1].tokenAddress, 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, "underlyingTokenAddress[1]"
        );
        assertEq(dv.underlyingTokenSymbols.length, 2, "underlyingTokenSymbolsLen");
        assertEq(dv.underlyingTokenSymbols[0].symbol, "WETH", "underlyingTokenSymbols[0]");
        assertEq(dv.underlyingTokenSymbols[1].symbol, "cbETH", "underlyingTokenSymbols[1]");
        assertEq(dv.underlyingTokenValueHeld.length, 2, "underlyingTokenValueHeldLen");
        assertEq(dv.underlyingTokenValueHeld[0].valueHeldInEth, 0, "underlyingTokenValueHeld[0]");
        assertEq(dv.underlyingTokenValueHeld[1].valueHeldInEth, 0, "underlyingTokenValueHeld[0]");
        assertEq(dv.lstStatsData.length, 0, "lstStatsDataLen");
    }
}
