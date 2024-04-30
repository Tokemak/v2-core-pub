// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-states-count */

import { Test } from "forge-std/Test.sol";

import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { LMPVault } from "src/vault/LMPVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { CurveV1StableSwap } from "src/swapper/adapters/CurveV1StableSwap.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { STETH_MAINNET } from "test/utils/Addresses.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { TokenReturnSolver } from "test/mocks/TokenReturnSolver.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";

contract AutoPoolTests is Test {
    address internal constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address internal constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    function _setUp(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
    }
}

contract RedeemTests is AutoPoolTests {
    SystemRegistry internal _systemRegistry;

    function setUp() public virtual {
        _setUp(19_386_214);

        vm.startPrank(V2_DEPLOYER);

        _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);

        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, V2_DEPLOYER);

        SwapRouter swapRouter = new SwapRouter(_systemRegistry);
        _systemRegistry.setSwapRouter(address(swapRouter));

        CurveV1StableSwap curveV1Swap = new CurveV1StableSwap(address(swapRouter), address(_systemRegistry.weth()));

        // route STETH_MAINNET -> ETH
        ISwapRouter.SwapData[] memory stEthToEthRoute = new ISwapRouter.SwapData[](1);
        stEthToEthRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            swapper: curveV1Swap,
            data: abi.encode(1, 0) // SellIndex, BuyIndex
         });
        swapRouter.setSwapRoute(STETH_MAINNET, stEthToEthRoute);

        vm.stopPrank();
    }

    function test_Redeem() public {
        vm.startPrank(V2_DEPLOYER);

        LMPVault pool = LMPVault(0x21eB47113E148839c30E1A9CA2b00Ea1317b50ed);
        IWETH9 weth = IWETH9(pool.asset());
        uint256 startingBalance = weth.balanceOf(V2_DEPLOYER);
        assertEq(startingBalance, 0.699e18, "startingBalance");

        address sharesHolder = 0x804986F81826034F7753484B936A634c706f1aDF;
        uint256 sharesToBurn = pool.balanceOf(sharesHolder);

        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        accessController.grantRole(Roles.LMP_DEBT_REPORTING_EXECUTOR, V2_DEPLOYER);

        uint256 assets = pool.redeem(sharesToBurn, V2_DEPLOYER, sharesHolder);

        assertEq(assets, 15.479430294412169634e18, "receivedAssets");

        vm.stopPrank();
    }
}

contract ShutdownDestination is AutoPoolTests {
    LMPVault internal _pool;
    SystemRegistry internal _systemRegistry;

    function setUp() public {
        _setUp(19_640_105);
        _pool = LMPVault(0x57FA6bb127a428Fe268104AB4d170fe4a99B73B6);
        _systemRegistry = SystemRegistry(address(_pool.getSystemRegistry()));
    }

    function test_DestinationShutdownReleasesAssetsAndCanRemove() public {
        AccessController accessController = AccessController(address(_systemRegistry.accessController()));
        // stETH/ETH-ng
        DestinationVault destinationToShutdown = DestinationVault(0xba1a495630a948f0942081924a5682f4f55E3e82);
        IWETH9 baseAsset = _systemRegistry.weth();

        TokenReturnSolver solver = new TokenReturnSolver(vm);

        // Shutdown Vault
        vm.startPrank(V2_DEPLOYER);
        destinationToShutdown.shutdown(IDestinationVault.VaultShutdownStatus.Deprecated);
        accessController.grantRole(Roles.SOLVER, address(this));
        vm.stopPrank();

        uint256 amountWethFromRebalance = 26.35e18;

        bytes memory data = solver.buildForIdleIn(_pool, amountWethFromRebalance);

        uint256 previousBalance = baseAsset.balanceOf(address(_pool));
        uint256 previousIdle = _pool.getAssetBreakdown().totalIdle;

        _pool.flashRebalance(
            solver,
            IStrategy.RebalanceParams({
                destinationOut: address(destinationToShutdown),
                tokenOut: address(destinationToShutdown.underlying()),
                amountOut: 25.692933029349164507e18,
                destinationIn: address(_pool),
                tokenIn: _pool.asset(),
                amountIn: amountWethFromRebalance
            }),
            data
        );

        assertEq(baseAsset.balanceOf(address(_pool)), previousBalance + amountWethFromRebalance, "bal");
        assertEq(_pool.getAssetBreakdown().totalIdle, previousIdle + amountWethFromRebalance, "idle");

        vm.startPrank(V2_DEPLOYER);
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(destinationToShutdown);
        _pool.removeDestinations(toRemove);
        vm.stopPrank();
    }
}
