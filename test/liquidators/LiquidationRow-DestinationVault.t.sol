/* solhint-disable func-name-mixedcase,contract-name-camelcase */
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { ILMPVaultRegistry, LMPVaultRegistry } from "src/vault/LMPVaultRegistry.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { IConvexRewardPool } from "src/interfaces/external/convex/IConvexRewardPool.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { Roles } from "src/libs/Roles.sol";
import {
    ZERO_EX_MAINNET,
    CVX_MAINNET,
    WETH_MAINNET,
    TOKE_MAINNET,
    CONVEX_BOOSTER,
    CURVE_META_REGISTRY_MAINNET,
    BAL_VAULT,
    AURA_MAINNET,
    AURA_BOOSTER,
    BAL_MAINNET
} from "test/utils/Addresses.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

/**
 * @notice This file is a test to ensure that the flow from DestinationVault to LiquidationRow to BaseAsyncSwapper works
 * as expected.
 *
 * It tests the CurveConvexDestinationVault and BalancerAuraDestinationVault.
 *
 * This includes running a scenario for each of the pools supported by the DestinationVaults.
 * The scenarios involve:
 * 1. Deploying the DestinationVault from the factory,
 * 2. Depositing tokens into the vault,
 * 3. Advancing time to claim rewards,
 * 4. Claiming rewards through LiquidationRow,
 * 5. Liquidating the rewards via LiquidationRow and ZeroEx Swapper (BaseAsyncSwapper).
 */
contract LiquidationRowTest is Test {
    SystemRegistry internal systemRegistry;
    DestinationVaultRegistry internal destinationVaultRegistry;
    LMPVaultRegistry internal lmpVaultRegistry;
    DestinationVaultFactory internal destinationVaultFactory;
    DestinationRegistry internal destinationTemplateRegistry;
    IAccessController internal accessController;
    LiquidationRow internal liquidationRow;
    BaseAsyncSwapper internal swapper;
    TestIncentiveCalculator internal testIncentiveCalculator;

    /**
     * @notice Set up the minimal system for the tests
     */
    function setUp() public virtual {
        // @comment
        // say that we need to work on a forked block because the hardcoded swap data might be only valid for a specific
        // block
        uint256 _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_161_835);
        vm.selectFork(_mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        destinationTemplateRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destinationTemplateRegistry));

        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 1, 1000);
        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        lmpVaultRegistry = new LMPVaultRegistry(systemRegistry);
        systemRegistry.setLMPVaultRegistry(address(lmpVaultRegistry));

        CurveResolverMainnet curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        systemRegistry.setCurveResolver(address(curveResolver));

        liquidationRow = new LiquidationRow(systemRegistry);

        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));
        accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(liquidationRow));
        accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));
        accessController.grantRole(Roles.REGISTRY_UPDATER, address(this));

        // @comment
        // This contract (address(this)) will be calling the destination vaults as a Vault.
        // We don't want to implement IVault in this contract, so we just mock this part of the system.
        vm.mockCall(
            address(lmpVaultRegistry), abi.encodeWithSelector(ILMPVaultRegistry.isVault.selector), abi.encode(true)
        );

        systemRegistry.addRewardToken(WETH_MAINNET);

        swapper = new BaseAsyncSwapper(ZERO_EX_MAINNET);
        liquidationRow.addToWhitelist(address(swapper));
    }
}

contract CurveIntegrationTest is LiquidationRowTest {
    // Some properties aren't actually used in the test, but are included for informational and debug purposes
    struct CurvePoolInfo {
        string name;
        address stats;
        address curvePool;
        address curveLpToken;
        address[2] curvePoolTokens;
        address convexStaking;
        uint256 convexPoolId;
        uint256 sellAmount;
        uint256 buyAmount;
        bytes swapperData;
    }

    CurveConvexDestinationVault private _vault;

    function setUp() public virtual override {
        super.setUp();

        CurveConvexDestinationVault dvTemplate =
            new CurveConvexDestinationVault(systemRegistry, CVX_MAINNET, CONVEX_BOOSTER);
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = keccak256(abi.encode("curve template"));
        destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);

        destinationTemplateRegistry.register(dvTypes, dvAddresses);
    }

    function runScenario(CurvePoolInfo memory poolInfo) public {
        address underlyer = poolInfo.curveLpToken;
        testIncentiveCalculator = new TestIncentiveCalculator(underlyer);
        address convexStaking = poolInfo.convexStaking;
        uint256 periodFinish = IConvexRewardPool(convexStaking).periodFinish();

        // Some pools might have a reward period that has ended. We need to queue new rewards in that case.
        // If reward period is over, queue new rewards
        if (periodFinish < block.timestamp) {
            address operator = IConvexRewardPool(convexStaking).operator();
            vm.prank(operator);
            IConvexRewardPool(convexStaking).queueNewRewards(1e18);
        }

        // Deploy the destination vault from the factory
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: poolInfo.curvePool,
            convexStaking: convexStaking,
            convexPoolId: poolInfo.convexPoolId,
            baseAssetBurnTokenIndex: 0
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            destinationVaultFactory.create(
                "curve template",
                WETH_MAINNET,
                address(underlyer),
                address(testIncentiveCalculator),
                new address[](0), // additionalTrackedTokens
                keccak256("salt1"),
                initParamBytes
            )
        );

        CurveConvexDestinationVault vault = CurveConvexDestinationVault(newVault);

        // Mint some LP tokens to this contract and verify that it worked
        deal(underlyer, address(this), 10 * 1e18);
        assertEq(IERC20(underlyer).balanceOf(address(this)), 10 * 1e18);

        // Approve the vault to spend the LP tokens and deposit them
        IERC20(underlyer).approve(address(vault), 10 * 1e18);
        vault.depositUnderlying(1e18);

        uint256 cvxBalanceBefore = liquidationRow.totalBalanceOf(CVX_MAINNET);

        // Move forward 30 days to claim rewards
        vm.roll(block.number + 7200 * 30);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 30 days);

        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        vaults[0] = vault;

        // Claim rewards using LiquidationRow
        liquidationRow.claimsVaultRewards(vaults);

        uint256 cvxBalanceAfter = liquidationRow.totalBalanceOf(CVX_MAINNET);

        // Verify that the Liquidator received CVX tokens from claim
        assert(cvxBalanceAfter > cvxBalanceBefore);

        SwapParams memory swapParams = SwapParams(
            CVX_MAINNET, poolInfo.sellAmount, WETH_MAINNET, poolInfo.buyAmount, poolInfo.swapperData, new bytes(0)
        );

        // @comment Liquidate the rewards
        liquidationRow.liquidateVaultsForToken(CVX_MAINNET, address(swapper), vaults, swapParams);
    }

    function test_SupportCurveStethEthOriginal() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve stETH/ETH Original",
            stats: 0xaed4850Ce877C0e0b051EbfF9286074C9378205c,
            curvePool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            curveLpToken: 0x06325440D014e39736583c165C2963BA99fAf14E,
            curvePoolTokens: [0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84],
            convexStaking: 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
            convexPoolId: 25,
            sellAmount: 8_725_355_817_378,
            buyAmount: 21_273_353_542,
            swapperData: hex"6af479b20000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000007ef87bbe9a200000000000000000000000000000000000000000000000000000004e913cd16000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000072819578a28ba900547ced177d21b716"
        });

        runScenario(poolInfos);
    }

    function test_SupportCurveStethEthConcentrated() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve stETH/ETH Concentrated",
            stats: 0x9963282680a196a7366E8f7FdB5690A85475346b,
            curvePool: 0x828b154032950C8ff7CF8085D841723Db2696056,
            curveLpToken: 0x828b154032950C8ff7CF8085D841723Db2696056,
            curvePoolTokens: [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84],
            convexStaking: 0xA61b57C452dadAF252D2f101f5Ba20aA86152992,
            convexPoolId: 155,
            sellAmount: 4_030_672_652_803,
            buyAmount: 9_827_212_649,
            swapperData: hex"6af479b20000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000003aa76cfca030000000000000000000000000000000000000000000000000000000244b4c3aa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000005f410ca3e8ff6db49ffccab94b79bde3"
        });

        runScenario(poolInfos);
    }

    function test_SupportCurveStethEthNg() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve stETH/ETH ng",
            stats: 0x78790F3479f6f36815065C6B7772C8b4E26BB412,
            curvePool: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
            curveLpToken: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
            curvePoolTokens: [0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84],
            convexStaking: 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
            convexPoolId: 177,
            sellAmount: 5_452_563_377_511_044,
            buyAmount: 13_293_449_194_954,
            swapperData: hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000135f13d73b5a8400000000000000000000000000000000000000000000000000000bfc7bb6dd50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000cec007baf7b19b7bc846784c4392c9a0"
        });

        runScenario(poolInfos);
    }

    function test_SupportCurveRethWstEth() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve rETH/wstETH",
            stats: 0xCbF6B043eD8dcda3280cA422a440276c5166D8Da,
            curvePool: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
            curveLpToken: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
            curvePoolTokens: [0xae78736Cd615f374D3085123A210448E74Fc6393, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0],
            convexStaking: 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc,
            convexPoolId: 73,
            sellAmount: 85_185_404_656_604,
            buyAmount: 207_691_048_792,
            swapperData: hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000004d79c5c8dbdc0000000000000000000000000000000000000000000000000000002ff0cdfffc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd000000000000"
        });

        runScenario(poolInfos);
    }

    function test_SupportCurveRethEth() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve rETH/ETH",
            stats: 0x27165a224461ec7B62E9f9b58d4c42CB848e0D82,
            curvePool: 0x0f3159811670c117c372428D4E69AC32325e4D0F,
            curveLpToken: 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C,
            curvePoolTokens: [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xae78736Cd615f374D3085123A210448E74Fc6393],
            convexStaking: 0x65C8aa24db76e870DEDfC35701eff84de405D1ba,
            convexPoolId: 154,
            sellAmount: 11_368_084_737_523,
            buyAmount: 27_716_609_671,
            swapperData: hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000a56d6a70df30000000000000000000000000000000000000000000000000000000665d1e642000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000"
        });

        runScenario(poolInfos);
    }

    function test_SupportCurveCbethEth() public {
        CurvePoolInfo memory poolInfos = CurvePoolInfo({
            name: "Curve cbETH/ETH",
            stats: 0x177B9FB826F79a2c0d590F418AC9517E71eA4272,
            curvePool: 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A,
            curveLpToken: 0x5b6C539b224014A09B3388e51CaAA8e354c959C8,
            curvePoolTokens: [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704],
            convexStaking: 0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699,
            convexPoolId: 127,
            sellAmount: 4_697_784_060_887_741,
            buyAmount: 11_453_341_389_396,
            swapperData: hex"6af479b200000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000010b09c162e42bd00000000000000000000000000000000000000000000000000000a53bcb9ee1c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000424e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0001f46b175474e89094c44da98b954eedeac495271d0f0001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000005cffdf19488bc70a77e818fa4074b825"
        });

        runScenario(poolInfos);
    }
}

contract BalancerAuraDestinationVaultIntegrationTest is LiquidationRowTest {
    // @comment
    // Some properties aren't actually used in the test, but are included for informational and debug purposes
    struct BalancerPoolInfo {
        string name;
        address stats;
        address balancerPool;
        address balancerLpToken;
        address[2] balancerTokens;
        address auraStaking;
        uint256 auraPoolId;
        uint256 sellAmount;
        uint256 buyAmount;
        bytes swapperData;
    }

    BalancerAuraDestinationVault private _vault;

    // Function to set up the test environment
    function setUp() public virtual override {
        super.setUp();

        // Add template to destinationTemplateRegistry
        BalancerAuraDestinationVault dvTemplate =
            new BalancerAuraDestinationVault(systemRegistry, BAL_VAULT, AURA_MAINNET);
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = keccak256(abi.encode("balancer template"));
        destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);

        destinationTemplateRegistry.register(dvTypes, dvAddresses);
    }

    function runScenario(BalancerPoolInfo memory poolInfo) public {
        address underlyer = poolInfo.balancerLpToken;
        testIncentiveCalculator = new TestIncentiveCalculator(underlyer);
        address auraStaking = poolInfo.auraStaking;
        uint256 periodFinish = IConvexRewardPool(auraStaking).periodFinish();

        // Some pools might have a reward period that has ended. We need to queue new rewards in that case.
        // If reward period is over, queue new rewards
        if (periodFinish < block.timestamp) {
            address operator = IConvexRewardPool(auraStaking).operator();
            vm.prank(operator);
            IConvexRewardPool(auraStaking).queueNewRewards(1e18);
        }

        // Deploy the destination vault from the factory
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: poolInfo.balancerPool,
            auraStaking: poolInfo.auraStaking,
            auraBooster: AURA_BOOSTER,
            auraPoolId: poolInfo.auraPoolId
        });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            destinationVaultFactory.create(
                "balancer template",
                WETH_MAINNET,
                address(underlyer),
                address(testIncentiveCalculator),
                new address[](0), // additionalTrackedTokens
                keccak256("salt1"),
                initParamBytes
            )
        );

        BalancerAuraDestinationVault vault = BalancerAuraDestinationVault(newVault);

        // Mint some LP tokens to this contract and verify that it worked
        deal(underlyer, address(this), 10 * 1e18);
        assertEq(IERC20(underlyer).balanceOf(address(this)), 10 * 1e18);

        // Approve the vault to spend the LP tokens and deposit them
        IERC20(underlyer).approve(address(vault), 10 * 1e18);
        vault.depositUnderlying(1e18);

        uint256 balBalanceBefore = liquidationRow.totalBalanceOf(BAL_MAINNET);

        // Move forward 30 days to claim rewards
        vm.roll(block.number + 7200 * 30);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 30 days);

        IDestinationVault[] memory vaults = new IDestinationVault[](1);
        vaults[0] = vault;

        // Claim rewards using LiquidationRow
        liquidationRow.claimsVaultRewards(vaults);

        uint256 balBalanceAfter = liquidationRow.totalBalanceOf(BAL_MAINNET);

        // Verify that the Liquidator received CVX tokens from claims
        assert(balBalanceAfter > balBalanceBefore);

        SwapParams memory swapParams = SwapParams(
            BAL_MAINNET, poolInfo.sellAmount, WETH_MAINNET, poolInfo.buyAmount, poolInfo.swapperData, new bytes(0)
        );

        liquidationRow.liquidateVaultsForToken(BAL_MAINNET, address(swapper), vaults, swapParams);
    }

    function test_SupportBalWstEthweth() public {
        BalancerPoolInfo memory poolInfos = BalancerPoolInfo({
            name: "Balancer wstETH/WETH",
            stats: 0x04d92eD35804a5633Ec5074299103134454C782c,
            balancerPool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            balancerLpToken: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
            balancerTokens: [0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2],
            auraStaking: 0x59D66C58E83A26d6a0E35114323f65c3945c89c1,
            auraPoolId: 115,
            sellAmount: 5_837_212_569_040_887,
            buyAmount: 12_458_940_887_601,
            swapperData: hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000014bce9f5a7f7f700000000000000000000000000000000000000000000000000000b37d0a36fc400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ba100000625a3754423978a60c9317c58a424e3d000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd0000000000000000000000001000000000000000000000000000000000"
        });

        runScenario(poolInfos);

        assertTrue(true);
    }

    function test_SupportBalRethWeth() public {
        BalancerPoolInfo memory poolInfos = BalancerPoolInfo({
            name: "Balancer rETH/WETH",
            stats: 0x3e097470a99100ED038688A7C548Fb7cB59b4086,
            balancerPool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
            balancerLpToken: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
            balancerTokens: [0xae78736Cd615f374D3085123A210448E74Fc6393, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2],
            auraStaking: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
            auraPoolId: 109,
            sellAmount: 221_551_179_953_609_125,
            buyAmount: 352_495_169_641_952,
            swapperData: hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000003131b9fd4b419a500000000000000000000000000000000000000000000000000013d62f5e0b9bc00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ba100000625a3754423978a60c9317c58a424e3d000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000d4add99ecb7670968f07cdcd61793159"
        });

        runScenario(poolInfos);

        assertTrue(true);
    }
}
