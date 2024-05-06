// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { ISystemRegistry, SystemRegistry } from "src/SystemRegistry.sol";
import { AutopoolRegistry } from "src/vault/AutopoolRegistry.sol";
import { AutopilotRouter } from "src/vault/AutopilotRouter.sol";
import { IAutopoolFactory, AutopoolFactory } from "src/vault/AutopoolFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { AutopoolMainRewarder, MainRewarder } from "src/rewarders/AutopoolMainRewarder.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { Roles } from "src/libs/Roles.sol";
import { TestWETH9 } from "test/mocks/TestWETH9.sol";
import { TOKE_MAINNET, USDC_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";

contract BaseTest is Test {
    // if forking is required at specific block, set this in sub-contract's setup before calling parent
    uint256 internal forkBlock;

    mapping(bytes => address) internal _tokens;

    IERC20 public baseAsset;

    SystemRegistry public systemRegistry;

    AutopoolRegistry public autoPoolRegistry;
    AutopilotRouter public autoPoolRouter;
    IAutopoolFactory public autoPoolFactory;

    DestinationVaultRegistry public destinationVaultRegistry;
    DestinationVaultFactory public destinationVaultFactory;

    TestIncentiveCalculator public testIncentiveCalculator;

    IAccessController public accessController;

    SystemSecurity public systemSecurity;

    address public autoPoolTemplate;

    // -- Staking -- //
    AccToke public accToke;
    uint256 public constant MIN_STAKING_DURATION = 30 days;

    // -- tokens -- //
    IERC20 public usdc;
    IERC20 public toke;
    IWETH9 public weth;

    // -- generally useful values -- //
    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant ONE_MONTH = 30 days;

    uint256 public constant WETH_INIT_DEPOSIT = 100_000;

    function setUp() public virtual {
        _setUp(true);
    }

    function _setUp(bool toFork) public {
        if (toFork) {
            fork();
        }

        //////////////////////////////////////
        // Set up misc labels
        //////////////////////////////////////
        toke = IERC20(TOKE_MAINNET);
        usdc = IERC20(USDC_MAINNET);

        if (toFork) {
            weth = IWETH9(WETH_MAINNET);
            baseAsset = IERC20(address(weth));
        } else {
            uint256 amt = uint256(1_000_000_000_000_000_000_000_000);
            TestWETH9 _baseAsset = new TestWETH9();
            _baseAsset.mint(address(this), amt);
            baseAsset = IERC20(_baseAsset);
            weth = IWETH9(address(_baseAsset));
        }

        vm.label(address(toke), "TOKE");
        vm.label(address(usdc), "USDC");
        vm.label(address(weth), "WETH");

        //////////////////////////////////////
        // Set up system registry
        //////////////////////////////////////

        systemRegistry = new SystemRegistry(TOKE_MAINNET, address(weth));

        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        autoPoolRegistry = new AutopoolRegistry(systemRegistry);
        systemRegistry.setAutopoolRegistry(address(autoPoolRegistry));
        // TODO: replace below 2 lines with `deployAutopilotRouter`
        autoPoolRouter = new AutopilotRouter(systemRegistry);
        systemRegistry.setAutopilotRouter(address(autoPoolRouter));

        systemSecurity = new SystemSecurity(systemRegistry);
        systemRegistry.setSystemSecurity(address(systemSecurity));
        vm.label(address(systemRegistry), "System Registry");
        vm.label(address(accessController), "Access Controller");

        systemRegistry.addRewardToken(address(baseAsset));
        systemRegistry.addRewardToken(address(TOKE_MAINNET));

        autoPoolTemplate = address(new AutopoolETH(systemRegistry, address(baseAsset)));

        autoPoolFactory = new AutopoolFactory(systemRegistry, autoPoolTemplate, 800, 100);
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
        systemRegistry.setAutopoolFactory(VaultTypes.LST, address(autoPoolFactory));

        // NOTE: these pieces were taken out so that each set of tests can init only the components it needs!
        //       Saves a ton of unnecessary setup time and makes fuzzing tests run much much faster
        //       (since these unnecessary (in those cases) setup times add up)
        //       (Left the code for future reference)
        // autoPoolRegistry = new AutopoolRegistry(systemRegistry);
        // systemRegistry.setAutopoolRegistry(address(autoPoolRegistry));
        // autoPoolRouter = new AutopilotRouter(WETH_MAINNET);
        // systemRegistry.setAutopilotRouter(address(autoPoolRouter));
        // autoPoolFactory = new AutopoolFactory(systemRegistry);
        // systemRegistry.setAutopoolFactory(VaultTypes.LST, address(autoPoolFactory));
        // // NOTE: deployer grants factory permission to update the registry
        // accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));
    }

    function fork() internal {
        // BEFORE WE DO ANYTHING, FORK!!
        uint256 mainnetFork;
        if (forkBlock == 0) {
            mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        } else {
            mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), forkBlock);
        }

        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork, "forks don't match");
    }

    function mockAsset(string memory name, string memory symbol, uint256 initialBalance) public returns (MockERC20) {
        MockERC20 newMock = new MockERC20(name, symbol, 18);
        if (initialBalance > 0) {
            deal(address(newMock), msg.sender, initialBalance);
        }

        return newMock;
    }

    function createMainRewarder(address asset, bool allowExtras) public returns (MainRewarder) {
        return createMainRewarder(asset, makeAddr("stakeTracker"), allowExtras);
    }

    // solhint-disable-next-line no-unused-vars
    function createMainRewarder(address asset, address autoPool, bool allowExtras) public returns (MainRewarder) {
        // We use mock since this function is called not from owner and
        // SystemRegistry.addRewardToken is not accessible from the ownership perspective
        vm.mockCall(
            address(systemRegistry), abi.encodeWithSelector(ISystemRegistry.isRewardToken.selector), abi.encode(true)
        );
        MainRewarder mainRewarder = MainRewarder(
            new AutopoolMainRewarder(
                systemRegistry, // registry
                asset,
                800, // newRewardRatio
                100, // durationInBlock
                allowExtras,
                autoPool
            )
        );
        vm.label(address(mainRewarder), "Main Rewarder");

        return mainRewarder;
    }

    function deployAccToke() public {
        if (address(accToke) != address(0)) return;

        accToke = new AccToke(
            systemRegistry,
            //solhint-disable-next-line not-rely-on-time
            block.timestamp, // start epoch
            MIN_STAKING_DURATION
        );

        vm.label(address(accToke), "AccToke");

        systemRegistry.setAccToke(address(accToke));
    }

    function deployAutopoolRegistry() public {
        if (address(autoPoolRegistry) != address(0)) return;

        autoPoolRegistry = new AutopoolRegistry(systemRegistry);
        systemRegistry.setAutopoolRegistry(address(autoPoolRegistry));
    }

    function deployAutopilotRouter() public {
        if (address(autoPoolRouter) != address(0)) return;

        autoPoolRouter = new AutopilotRouter(systemRegistry);
        systemRegistry.setAutopilotRouter(address(autoPoolRouter));
    }

    function deployAutopoolFactory() public {
        if (address(autoPoolFactory) != address(0)) return;

        autoPoolFactory = new AutopoolFactory(systemRegistry, autoPoolTemplate, 800, 100);
        systemRegistry.setAutopoolFactory(VaultTypes.LST, address(autoPoolFactory));
        // NOTE: deployer grants factory permission to update the registry
        accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(autoPoolFactory));

        vm.label(address(autoPoolFactory), "Autopool Vault Factory");
    }

    function createAndPrankUser(string memory label) public returns (address) {
        return createAndPrankUser(label, 0);
    }

    function createAndPrankUser(string memory label, uint256 tokeBalance) public returns (address) {
        address user = makeAddr(label);

        if (tokeBalance > 0) {
            deal(address(toke), user, tokeBalance);
        }

        return user;
    }
}
