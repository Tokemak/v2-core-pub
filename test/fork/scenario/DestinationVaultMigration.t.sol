// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,avoid-low-level-calls */

import { Test } from "forge-std/Test.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { WETH_MAINNET, CVX_MAINNET } from "test/utils/Addresses.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { ZeroCalculator } from "src/stats/calculators/ZeroCalculator.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";

contract DestinationVaultMigrationTests is Test {
    uint256 public defaultRewardRatioDest = 10_000;
    uint256 public defaultRewardBlockDurationDest = 10;
    address public currentOwner = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;
    SystemRegistry public systemRegistry = SystemRegistry(0x2218F90A98b0C070676f249EF44834686dAa4285);

    DestinationVault public currentDestinationVault = DestinationVault(0xE382BBd32C4E202185762eA433278f4ED9E6151E);
    AutopoolETH public autoETH = AutopoolETH(0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56);

    address public flashBorrowSolver = 0x952D7a7eB2e0804d37d9244BE8e47341356d2f5D;
    bytes32 public solverExecRole = 0x4208d9aa7c658dc4c5bcda3bc04e7a99676d37c39bb0ff92589c9a5c464646a4;
    address public flashBorrowSolverAdmin = 0x123cC4AFA59160C6328C0152cf333343F510e5A3;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_902_978);
        vm.selectFork(mainnetFork);
    }

    function test_MigrateDestinationVault() public {
        // Get references from the current system
        DestinationVaultRegistry dvRegistry =
            DestinationVaultRegistry(address(systemRegistry.destinationVaultRegistry()));
        AccessController accessController = AccessController(address(systemRegistry.accessController()));
        IStatsCalculatorRegistry statCalcRegistry = systemRegistry.statsCalculatorRegistry();

        // Begin by deploying a new DestinationVaultFactory. This will include the updated
        // DestinationVaultRewarder with the fixes
        DestinationVaultFactory newFactory =
            new DestinationVaultFactory(systemRegistry, defaultRewardRatioDest, defaultRewardBlockDurationDest);

        // Also deploy our Zero Stats Calculator
        ZeroCalculator zeroCalculator = new ZeroCalculator();

        vm.startPrank(currentOwner);

        // Allow configuring the new factory on the registry
        accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));

        // Allow creating new Destinations
        accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));

        // Allow add/remove of destinations from the Autopool
        accessController.grantRole(Roles.AUTO_POOL_DESTINATION_UPDATER, address(this));

        // Allow shutdown of destination vault
        accessController.grantRole(Roles.DESTINATION_VAULT_MANAGER, address(this));

        // Allow us to perform debtReporting
        accessController.grantRole(Roles.AUTO_POOL_REPORTING_EXECUTOR, address(this));

        vm.stopPrank();

        // Set the new factory
        dvRegistry.setVaultFactory(address(newFactory));

        // Deploy the new destination vault
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
            convexStaking: 0x3B793E505A3C7dbCb718Fe871De8eBEf7854e74b,
            convexPoolId: 271
        });
        bytes memory initParamBytes = abi.encode(initParams);

        DestinationVault newVault = DestinationVault(
            payable(
                newFactory.create(
                    "crv-ng-cvx-v1",
                    WETH_MAINNET,
                    0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D,
                    address(
                        statCalcRegistry.getCalculator(
                            keccak256(
                                abi.encode("incentive-v4-", CVX_MAINNET, 0x3B793E505A3C7dbCb718Fe871De8eBEf7854e74b)
                            )
                        )
                    ),
                    new address[](0), // additionalTrackedTokens
                    keccak256(abi.encodePacked(block.number, uint256(1))),
                    initParamBytes
                )
            )
        );
        address[] memory destVaultsList = new address[](1);
        destVaultsList[0] = address(newVault);

        // Add the Destination to the Autopool
        autoETH.addDestinations(destVaultsList);
        destVaultsList[0] = address(currentDestinationVault);
        autoETH.removeDestinations(destVaultsList);

        // Verify LP tokens match
        assertEq(currentDestinationVault.underlying(), newVault.underlying(), "underlying");

        // Perform a debt reporting so prices stay the same
        autoETH.updateDebtReporting(10);

        uint256 autopoolStartingTotalSupply = autoETH.totalSupply();
        uint256 autopoolStartingTotalAssets = autoETH.totalAssets();

        uint256 oldInternalDebtBal = currentDestinationVault.internalDebtBalance();
        uint256 oldInternalQueriedBal = currentDestinationVault.internalQueriedBalance();
        uint256 oldExternalDebtBal = currentDestinationVault.externalDebtBalance();
        uint256 oldExternalQueriedBal = currentDestinationVault.externalQueriedBalance();

        // Verify the value state is as we'd expect
        assertTrue(oldExternalDebtBal > 0, "oldExternalDebtBalExists");
        assertTrue(oldExternalQueriedBal > 0, "oldExternalQueriedBalExists");
        assertEq(oldInternalDebtBal, 0, "oldInternalDebtBalZero");
        assertEq(oldInternalQueriedBal, 0, "oldInternalQueriedBalZero");

        // Shutdown the current destination and swap its calculator for "zero"
        currentDestinationVault.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        zeroCalculator.setLpTokenPool(currentDestinationVault.underlying(), currentDestinationVault.getPool());
        currentDestinationVault.setIncentiveCalculator(address(zeroCalculator));

        uint256 migrationAmount = currentDestinationVault.balanceOf(address(autoETH));

        // Setup the like-for-like rebalance
        {
            bytes32[] memory noop = new bytes32[](0);
            bytes[] memory nodata = new bytes[](0);
            bytes memory rebalancePayload = abi.encode(noop, nodata);

            // Params that tell the strategy old->new
            IStrategy.RebalanceParams memory rebalanceParams = IStrategy.RebalanceParams({
                destinationIn: address(newVault),
                tokenIn: address(newVault.underlying()),
                amountIn: migrationAmount,
                destinationOut: address(currentDestinationVault),
                tokenOut: address(currentDestinationVault.underlying()),
                amountOut: migrationAmount
            });

            // Grant ourselves the ability to execute a rebalance
            vm.prank(flashBorrowSolverAdmin);
            (bool grantFlashExecRoleResult,) = flashBorrowSolver.call(
                abi.encodeWithSignature("grantRole(bytes32,address)", solverExecRole, address(this))
            );
            assertEq(grantFlashExecRoleResult, true, "grantFlashExecRoleResult");

            // Perform the actual rebalance
            (bool rebalanceResult,) = flashBorrowSolver.call(
                abi.encodeCall(
                    IFlashBorrowSolver(flashBorrowSolver).execute, (address(autoETH), rebalanceParams, rebalancePayload)
                )
            );
            assertEq(rebalanceResult, true, "rebalanceResult");
        }

        {
            uint256 oldUpdatedInternalDebtBal = currentDestinationVault.internalDebtBalance();
            uint256 oldUpdatedInternalQueriedBal = currentDestinationVault.internalQueriedBalance();
            uint256 oldUpdatedExternalDebtBal = currentDestinationVault.externalDebtBalance();
            uint256 oldUpdatedExternalQueriedBal = currentDestinationVault.externalQueriedBalance();

            assertEq(oldUpdatedInternalDebtBal, 0, "oldUpdatedInternalDebtBal");
            assertEq(oldUpdatedInternalQueriedBal, 0, "oldUpdatedInternalQueriedBal");
            assertEq(oldUpdatedExternalDebtBal, oldExternalDebtBal - migrationAmount, "oldUpdatedExternalDebtBal");
            assertEq(
                oldUpdatedExternalQueriedBal, oldExternalQueriedBal - migrationAmount, "oldUpdatedExternalQueriedBal"
            );
        }

        {
            uint256 autopoolEndingTotalSupply = autoETH.totalSupply();
            uint256 autopoolEndingTotalAssets = autoETH.totalAssets();

            assertEq(autopoolStartingTotalSupply, autopoolEndingTotalSupply, "autopoolEndingTotalSupply");
            assertEq(autopoolStartingTotalAssets, autopoolEndingTotalAssets, "autopoolEndingTotalAssets");
        }

        {
            uint256 newVaultInternalDebtBal = newVault.internalDebtBalance();
            uint256 newVaultInternalQueriedBal = newVault.internalQueriedBalance();
            uint256 newVaultExternalDebtBal = newVault.externalDebtBalance();
            uint256 newVaultExternalQueriedBal = newVault.externalQueriedBalance();

            assertEq(newVault.balanceOf(address(autoETH)), migrationAmount, "newPoolMigrationAmt");
            assertEq(newVaultInternalDebtBal, 0, "newVaultInternalDebtBal");
            assertEq(newVaultInternalQueriedBal, 0, "newVaultInternalQueriedBal");
            assertEq(newVaultExternalDebtBal, migrationAmount, "newVaultExternalDebtBal");
            assertEq(newVaultExternalQueriedBal, migrationAmount, "newVaultExternalQueriedBal");
        }
    }
}

interface IFlashBorrowSolver {
    function execute(address vault, IStrategy.RebalanceParams calldata rebalanceParams, bytes calldata data) external;
}
