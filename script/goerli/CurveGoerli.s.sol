// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable no-console
// solhint-disable max-states-count

import { console } from "forge-std/console.sol";

import { ERC20Mock } from "script/contracts/mocks/ERC20Mock.sol";

import { VyperDeployer } from "script/utils/VyperDeployer.sol";
import { MockCurveRegistry } from "script/contracts/mocks/MockCurveRegistry.sol";
import { BaseScript, Systems } from "script/BaseScript.sol";

import { ICurvePool } from "script/interfaces/curve/ICurvePool.sol";
import { ICurvePoolNG } from "script/interfaces/curve/ICurvePoolNG.sol";
import { ICurveTokenV5 } from "script/interfaces/curve/ICurveTokenV5.sol";
import { IStableSwapInitializable } from "script/interfaces/curve/IStableSwapInitializable.sol";

/**
 * This script deploys three Curve StableSwap pools, and one Curve CryptoSwap pool.  This script also deploys a
 *      mocked version of of the Curve MetaRegistry.  All pools params have been taken from Etherscan based on pools
 *      that TokemakV2 will interact with on mainnet.  These pools are stEth / Eth (v1), stEth / Eth concentrated (v1),
 *      stEth / Eth ng (v1), and cbEth / Eth (v2).  The one pool left out is rEth / Eth (v2), this is because it uses
 *      the same contract as the cbEth / Eth pool.
 */
contract CurveGoerli is BaseScript {
    uint256 public constant LIQUIDITY_AMOUNT = 5e18;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20Mock public weth;
    ERC20Mock public stEth;
    ERC20Mock public cbEth;

    MockCurveRegistry public curveRegistry;

    address public goerliOwner;

    // Stableswap params

    /**
     * Stableswap Vyper version 0.2.8 - original stEth / Eth pool.  Values taken from contract here:
     *      https://etherscan.io/address/0xdc24316b9ae028f1497c275eb9192a3ea0f67022#readContract
     */
    address public originalStableSwapLp;
    uint256 public originalCurveStableSwapA = uint256(30);
    uint256 public originalCurveStableSwapFee = uint256(1_000_000);
    uint256 public originalCurveStableSwapAdminFee = uint256(5_000_000_000);
    address[2] public originalStableSwapTokensArr;

    /**
     * Stableswap Vyper version 0.2.15 - stEth / Eth concentrated pool.  Values taken from deploy txn
     *      here: https://etherscan.io/tx/0x6fbe1f718083e7eaf4d9e33a06e031218f1fd716d158b6cd15d4b0f48d1609f0
     */
    string public concentratedStableSwapName = "stEth concentrated";
    string public concentratedStableSwapSymbol = "stEth con";
    uint256 public concentratedStableSwapA = uint256(1000);
    uint256 public concentratedStableSwapFee = uint256(4_000_000);
    address[4] public concentratedStableSwapTokensArr;
    uint256[4] public concentratedStableSwapRateMultipliersArr =
        [uint256(10 ** 18), uint256(10 ** 18), uint256(0), uint256(0)];

    /**
     * Stbaleswap Vyper version 0.3.7 - stEth / Eth ng pool.  Values taken from deploy txn here:
     *      https://etherscan.io/tx/0x454cd95cc6189b118512f074eeffe6b0f73a569e6c54796a99af7f75716554ee
     */
    string public stableSwapNgName = "stEth Ng Pool";
    string public stableSwapNgSymbol = "stEth Ng";
    uint256 public stableSwapNgA = uint256(1500);
    uint256 public stableSwapNgFee = uint256(4_000_000);
    address[4] public stableSwapNgTokensArr;
    uint256[4] public stableSwapNgRateMultipliersArr = [uint256(10 ** 18), uint256(10 ** 18), uint256(0), uint256(0)];

    /**
     * Crypto params - taken from deploy txn here:
     *      https://etherscan.io/tx/0xaefdbf284442ae2aab0ce85697246371200809483a383a71d3a68bbc30913d25
     */
    uint256 public cryptoA = uint256(20_000_000);
    uint256 public cryptoGamma = uint256(10_000_000_000_000_000);
    uint256 public cryptoMidFee = uint256(5_000_000);
    uint256 public cryptoOutFee = uint256(45_000_000);
    uint256 public cryptoAllowedExtraProfit = uint256(10_000_000_000);
    uint256 public cryptoFeeGamma = uint256(5_000_000_000_000_000);
    uint256 public cryptoAdjustmentStep = uint256(5_500_000_000_000);
    uint256 public cryptoAdminFee = uint256(5_000_000_000);
    uint256 public cryptoMovingAverageHalfTime = uint256(600);
    uint256 public cryptoInitialPrice = uint256(1_010_101_010_101_010_200); // May want to change this.
    address public curveCryptoSwapLP;
    address[2] public cryptoTokensArr; // Set later in script.

    function run() external {
        setUp(Systems.LST_GEN1_GOERLI);
        vm.startBroadcast(vm.envUint(constants.privateKeyEnvVar));
        goerliOwner = vm.addr(vm.envUint(constants.privateKeyEnvVar));

        // Set up tokens
        weth = new ERC20Mock("Wrapped Eth - Mock", "wethMock");
        stEth = new ERC20Mock("Wrapped Staked Eth - Mock", "stEthMock");
        cbEth = new ERC20Mock("Coinbase Eth - Mock", "cbEthMock");

        console.log("Weth: ", address(weth));
        console.log("stEth: ", address(stEth));
        console.log("cbEth: ", address(cbEth));

        // TODO: May be able to be deleted depending on tokens in Constants.sol, amounts already minted.
        // Mint 15 tokens a piece
        weth.mint(goerliOwner, LIQUIDITY_AMOUNT * 3);
        stEth.mint(goerliOwner, LIQUIDITY_AMOUNT * 3);
        cbEth.mint(goerliOwner, LIQUIDITY_AMOUNT * 3);

        originalStableSwapTokensArr[0] = ETH;
        originalStableSwapTokensArr[1] = address(stEth);

        concentratedStableSwapTokensArr[0] = address(weth);
        concentratedStableSwapTokensArr[1] = address(stEth);

        stableSwapNgTokensArr[0] = ETH;
        stableSwapNgTokensArr[1] = address(stEth);

        cryptoTokensArr[0] = address(weth);
        cryptoTokensArr[1] = address(cbEth);

        //
        // Launch LP tokens.
        //
        originalStableSwapLp = VyperDeployer.deployVyperContract(
            "script/contracts/compiled/CurveTokenV5.json", abi.encode("Original stableswap lp", "lp")
        );
        console.log("Stableswap LP: ", originalStableSwapLp);

        curveCryptoSwapLP = VyperDeployer.deployVyperContract(
            "script/contracts/compiled/CurveTokenV5.json", abi.encode("Cryptoswap lp", "lp")
        );
        console.log("CryptoSwap LP: ", curveCryptoSwapLP);

        //
        // Launch pools.
        //

        // Stableswap Vyper version 0.2.8 - stEth / Eth.
        address deployedAddressStableSwap = VyperDeployer.deployVyperContract(
            "script/contracts/compiled/CurveStableSwapV028.json",
            abi.encode(
                goerliOwner,
                originalStableSwapTokensArr,
                originalStableSwapLp,
                originalCurveStableSwapA,
                originalCurveStableSwapFee,
                originalCurveStableSwapAdminFee
            )
        );
        console.log("Stableswap: ", deployedAddressStableSwap);

        /**
         * Stableswap Vyper version 0.2.15 - stEth / Eth concentrated. LP token part of pool.
         *
         * Uses weth.
         */
        address deployedAddressStableSwapConcentrated =
            VyperDeployer.deployVyperContract("script/contracts/compiled/CurveStableSwapV0215.json", bytes(""));

        IStableSwapInitializable(deployedAddressStableSwapConcentrated).initialize(
            concentratedStableSwapName,
            concentratedStableSwapSymbol,
            concentratedStableSwapTokensArr,
            concentratedStableSwapRateMultipliersArr,
            concentratedStableSwapA,
            concentratedStableSwapFee
        );
        console.log("Stableswap concentrated: ", deployedAddressStableSwapConcentrated);

        // Stableswap Vyper version 0.3.7 - stEth / eth ng. LP token part of pool.
        address deployedAddressStableSwapNg =
            VyperDeployer.deployVyperContract("script/contracts/compiled/CurveStableSwapV037.json", bytes(""));

        IStableSwapInitializable(deployedAddressStableSwapNg).initialize(
            stableSwapNgName,
            stableSwapNgSymbol,
            stableSwapNgTokensArr,
            stableSwapNgRateMultipliersArr,
            stableSwapNgA,
            stableSwapNgFee
        );
        console.log("Stableswap ng: ", deployedAddressStableSwapNg);

        // Cryptoswap

        /**
         * Below encodings are done to avoid a stack too deep error when attempting
         *      to encode all variables for v2 pools at one time.
         */
        bytes memory abiEncodeOne = abi.encode(
            goerliOwner,
            goerliOwner, // Fee receiver
            cryptoA,
            cryptoGamma,
            cryptoMidFee,
            cryptoOutFee
        );
        bytes memory abiEncodeTwo = abi.encode(
            cryptoAllowedExtraProfit,
            cryptoFeeGamma,
            cryptoAdjustmentStep,
            cryptoAdminFee,
            cryptoMovingAverageHalfTime,
            cryptoInitialPrice,
            curveCryptoSwapLP,
            cryptoTokensArr
        );
        address deployedAddressCryptoSwap = VyperDeployer.deployVyperContract(
            "script/contracts/compiled/CurveCryptoSwapv031.json", abi.encodePacked(abiEncodeOne, abiEncodeTwo)
        );
        console.log("CryptoSwap: ", deployedAddressCryptoSwap);

        //
        // Supply liquidity to pools.
        //

        // Original stable swap.
        stEth.approve(deployedAddressStableSwap, LIQUIDITY_AMOUNT);
        ICurveTokenV5(originalStableSwapLp).set_minter(deployedAddressStableSwap);
        ICurvePool(deployedAddressStableSwap).add_liquidity{ value: LIQUIDITY_AMOUNT }(
            [LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT], 0
        );

        // Concentrated stable swap.
        stEth.approve(deployedAddressStableSwapConcentrated, LIQUIDITY_AMOUNT);
        weth.approve(deployedAddressStableSwapConcentrated, LIQUIDITY_AMOUNT);
        ICurvePool(deployedAddressStableSwapConcentrated).add_liquidity([LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT], 0);

        // Ng stable swap
        stEth.approve(deployedAddressStableSwapNg, LIQUIDITY_AMOUNT);
        ICurvePoolNG(deployedAddressStableSwapNg).set_oracle(bytes4(""), address(0)); // Set as zero on mainnet
        ICurvePool(deployedAddressStableSwapNg).add_liquidity{ value: LIQUIDITY_AMOUNT }(
            [LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT], 0
        );

        // Crypto
        cbEth.approve(deployedAddressCryptoSwap, LIQUIDITY_AMOUNT);
        weth.approve(deployedAddressCryptoSwap, LIQUIDITY_AMOUNT);
        ICurveTokenV5(curveCryptoSwapLP).set_minter(deployedAddressCryptoSwap);
        // Operates in Eth, can deposit weth.
        ICurvePool(deployedAddressCryptoSwap).add_liquidity([LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT], 0);

        //
        // Launch registry
        //
        curveRegistry = new MockCurveRegistry();
        console.log("Mock Curve Registry: ", address(curveRegistry));

        //
        // Set up registry
        //
        curveRegistry.setPool(deployedAddressStableSwap, address(originalStableSwapLp), 2);
        curveRegistry.setPool(deployedAddressStableSwapConcentrated, deployedAddressStableSwapConcentrated, 2);
        curveRegistry.setPool(deployedAddressStableSwapNg, deployedAddressStableSwapNg, 2);
        curveRegistry.setPool(deployedAddressCryptoSwap, curveCryptoSwapLP, 2);

        vm.stopBroadcast();
    }
}
