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

contract LiquidationRowTest is Test {
    address public constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address public constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;

    SystemRegistry internal _systemRegistry;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_386_214);
        vm.selectFork(forkId);

        vm.startPrank(V2_DEPLOYER);

        _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);

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
        accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, V2_DEPLOYER);

        uint256 assets = pool.redeem(sharesToBurn, V2_DEPLOYER, sharesHolder);

        assertEq(assets, 15.479430294412169634e18, "receivedAssets");

        vm.stopPrank();
    }
}
