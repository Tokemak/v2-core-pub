// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";

import { Roles } from "src/libs/Roles.sol";

import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";

contract Destinations is Script {
    uint256 public saltIx;
    Constants.Values public constants;

    struct CurveConvexSetup {
        string name;
        address curvePool;
        address curveLpToken;
        address convexStaking;
        uint256 convexPoolId;
    }

    struct BalancerAuraSetup {
        string name;
        address balancerPool;
        address auraStaking;
        uint256 auraPoolId;
    }

    function run() external {
        constants = Constants.get(Systems.LST_GEN2_MAINNET);

        vm.startBroadcast();

        (, address owner,) = vm.readCallers();

        constants.sys.accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        setupDestinations();

        constants.sys.accessController.revokeRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, owner);

        vm.stopBroadcast();
    }

    function setupDestinations() internal {
        setupCurveDestinations();
        setupBalancerDestinations();
    }

    function setupCurveDestinations() internal {
        setupCurveConvexDestinationVault(
            CurveConvexSetup({
                name: "stETH/ETH Original",
                curvePool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                curveLpToken: 0x06325440D014e39736583c165C2963BA99fAf14E,
                convexStaking: 0x0A760466E1B4621579a82a39CB56Dda2F4E70f03,
                convexPoolId: 25
            })
        );

        setupCurveConvexDestinationVault(
            CurveConvexSetup({
                name: "stETH/ETH NG",
                curvePool: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
                curveLpToken: 0x21E27a5E5513D6e65C4f830167390997aA84843a,
                convexStaking: 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8,
                convexPoolId: 177
            })
        );

        setupCurveConvexDestinationVault(
            CurveConvexSetup({
                name: "cbETH/ETH",
                curvePool: 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A,
                curveLpToken: 0x5b6C539b224014A09B3388e51CaAA8e354c959C8,
                convexStaking: 0x5d02EcD9B83f1187e92aD5be3d1bd2915CA03699,
                convexPoolId: 127
            })
        );

        setupCurveNGConvexDestinationVault(
            CurveConvexSetup({
                name: "osETH/rETH",
                curvePool: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                curveLpToken: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
                convexStaking: 0xBA7eBDEF7723e55c909Ac44226FB87a93625c44e,
                convexPoolId: 268
            })
        );

        setupCurveConvexDestinationVault(
            CurveConvexSetup({
                name: "rETH/wstETH",
                curvePool: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
                curveLpToken: 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08,
                convexStaking: 0x5c463069b99AfC9333F4dC2203a9f0c6C7658cCc,
                convexPoolId: 73
            })
        );
    }

    function setupBalancerDestinations() internal {
        setupBalancerAuraDestinationVault(
            BalancerAuraSetup({
                name: "wstETH/WETH",
                balancerPool: 0x32296969Ef14EB0c6d29669C550D4a0449130230,
                auraStaking: 0x59D66C58E83A26d6a0E35114323f65c3945c89c1,
                auraPoolId: 115
            })
        );

        setupBalancerAuraDestinationVault(
            BalancerAuraSetup({
                name: "rETH/WETH",
                balancerPool: 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276,
                auraStaking: 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D,
                auraPoolId: 109
            })
        );
    }

    function setupBalancerAuraDestinationVault(BalancerAuraSetup memory args) internal {
        BalancerAuraDestinationVault.InitParams memory initParams = BalancerAuraDestinationVault.InitParams({
            balancerPool: args.balancerPool,
            auraStaking: args.auraStaking,
            auraBooster: constants.ext.auraBooster,
            auraPoolId: args.auraPoolId
        });

        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                "bal-aura-v1",
                constants.tokens.weth,
                initParams.balancerPool,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        keccak256(abi.encode("incentive-v4-", constants.tokens.aura, args.auraStaking))
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Balancer ", args.name, " Dest Vault: "), address(newVault));
    }

    function setupCurveNGConvexDestinationVault(CurveConvexSetup memory args) internal {
        setupCurveConvexBaseDestinationVault(
            args.name, "crv-cvx-ng-v1", args.curvePool, args.curveLpToken, args.convexStaking, args.convexPoolId
        );
    }

    function setupCurveConvexDestinationVault(CurveConvexSetup memory args) internal {
        setupCurveConvexBaseDestinationVault(
            args.name, "crv-cvx-v1", args.curvePool, args.curveLpToken, args.convexStaking, args.convexPoolId
        );
    }

    function setupCurveConvexBaseDestinationVault(
        string memory name,
        string memory template,
        address curvePool,
        address curveLpToken,
        address convexStaking,
        uint256 convexPoolId
    ) internal {
        CurveConvexDestinationVault.InitParams memory initParams = CurveConvexDestinationVault.InitParams({
            curvePool: curvePool,
            convexStaking: convexStaking,
            convexPoolId: convexPoolId
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            constants.sys.destinationVaultFactory.create(
                template,
                constants.tokens.weth,
                curveLpToken,
                address(
                    constants.sys.statsCalcRegistry.getCalculator(
                        keccak256(abi.encode("incentive-v4-", constants.tokens.cvx, convexStaking))
                    )
                ),
                new address[](0), // additionalTrackedTokens
                keccak256(abi.encodePacked(block.number, saltIx++)),
                initParamBytes
            )
        );

        console.log(string.concat("Curve ", name, " Dest Vault: "), address(newVault));
    }
}
