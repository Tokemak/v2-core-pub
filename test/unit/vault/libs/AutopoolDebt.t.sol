// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase,max-states-count

import { AutopoolDebt } from "src/vault/libs/AutopoolDebt.sol";
import { Test } from "forge-std/Test.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { DestinationVaultMocks } from "test/unit/mocks/DestinationVaultMocks.t.sol";

contract AutopoolDebtTests is Test, DestinationVaultMocks {
    IDestinationVault internal destVaultOne;
    AutopoolDebt.DestinationInfo internal destVaultOneInfo;

    constructor() DestinationVaultMocks(vm) { }

    function setUp() public {
        destVaultOne = IDestinationVault(makeAddr("destVaultOne"));
        vm.mockCall(address(destVaultOne), abi.encodeWithSignature("decimals()"), abi.encode(18));
    }
}

contract RecalculateDestInfoTests is AutopoolDebtTests {
    function test_NewDebtIsMidPointOfCurrentMinMaxValue() external {
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        uint256 mid = 1500e18;
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, 1e18, 1e18);

        assertEq(result.totalDebtIncrease, mid);

        // New debt is also saved as the new cached debt value
        assertEq(destVaultOneInfo.cachedDebtValue, mid);
    }

    function test_MinDebtValueUsedAsMinDebtIncrease() external {
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, 1e18, 1e18);

        assertEq(result.totalMinDebtIncrease, min);

        // Min debt increase is also saved as the cached min debt value
        assertEq(destVaultOneInfo.cachedMinDebtValue, min);
    }

    function test_MaxDebtValueUsedAsMaxDebtIncrease() external {
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, 1e18, 1e18);

        assertEq(result.totalMaxDebtIncrease, max, "maxIncrease");

        // Min debt increase is also saved as the cached min debt value
        assertEq(destVaultOneInfo.cachedMaxDebtValue, max, "cachedMaxValue");
    }

    function test_DebtDecreaseTakesShareChangeIntoAccount() external {
        uint256 originalShares = 10e18;
        uint256 newShares = 10e18;
        uint256 shareChange = 5e18;
        uint256 min = 1000e18;
        uint256 max = 2000e18;

        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        destVaultOneInfo.cachedDebtValue = 90e18;
        destVaultOneInfo.ownedShares = originalShares;

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, originalShares - shareChange, newShares);

        // 90 value @ 10 shares, now we have 5 shares
        // remaining value should be 45;
        assertEq(result.totalDebtDecrease, 45e18);
    }

    function test_MinDebtDecreaseTakesShareChangeIntoAccount() external {
        uint256 originalShares = 10e18;
        uint256 newShares = 10e18;
        uint256 shareChange = 5e18;
        uint256 min = 1000e18;
        uint256 max = 2000e18;

        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        destVaultOneInfo.cachedMinDebtValue = 90e18;
        destVaultOneInfo.ownedShares = originalShares;

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, originalShares - shareChange, newShares);

        // 90 value @ 10 shares, now we have 5 shares
        // remaining value should be 45;
        assertEq(result.totalMinDebtDecrease, 45e18);
    }

    function test_MaxDebtDecreaseTakesShareChangeIntoAccount() external {
        uint256 originalShares = 10e18;
        uint256 newShares = 10e18;
        uint256 shareChange = 5e18;
        uint256 min = 1000e18;
        uint256 max = 2000e18;

        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        destVaultOneInfo.cachedMaxDebtValue = 90e18;
        destVaultOneInfo.ownedShares = originalShares;

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, originalShares - shareChange, newShares);

        // 90 value @ 10 shares, now we have 5 shares
        // remaining value should be 45;
        assertEq(result.totalMaxDebtDecrease, 45e18);
    }

    function test_AllDebtDecreasesAreZeroWhenNoSharesPreviouslyOwned() external {
        uint256 originalShares = 10e18;
        uint256 newShares = 10e18;
        uint256 shareChange = 5e18;
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        // With no shares previously owned, all cached values are 0
        destVaultOneInfo.cachedDebtValue = 0;
        destVaultOneInfo.cachedMinDebtValue = 0;
        destVaultOneInfo.cachedMaxDebtValue = 0;
        destVaultOneInfo.ownedShares = 0;

        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, originalShares - shareChange, newShares);

        assertEq(result.totalDebtDecrease, 0);
        assertEq(result.totalMinDebtDecrease, 0);
        assertEq(result.totalMaxDebtDecrease, 0);
    }

    function test_DebtInfoTimestampUpdatedToLatest() external {
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        assertNotEq(destVaultOneInfo.lastReport, block.timestamp);
        AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, 1e18, 1e18);

        assertEq(destVaultOneInfo.lastReport, block.timestamp);
    }

    function test_DebtInfoOwnedSharesUpdatedToCurrent() external {
        uint256 shares = 1e18;
        uint256 min = 1000e18;
        uint256 max = 2000e18;
        //_mockDestVaultDebtValues(address(destVaultOne), shares, min, max);
        _mockDestVaultRangePricesLP(address(destVaultOne), min, max, true);

        assertNotEq(destVaultOneInfo.ownedShares, block.timestamp);
        AutopoolDebt.recalculateDestInfo(destVaultOneInfo, destVaultOne, shares, shares);

        assertEq(destVaultOneInfo.ownedShares, shares);
    }
}
