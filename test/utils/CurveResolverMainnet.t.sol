// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { CurveResolverMainnet } from "src/utils/CurveResolverMainnet.sol";
import { ICurveMetaRegistry } from "src/interfaces/external/curve/ICurveMetaRegistry.sol";

contract CurveResolverMainnetTests is Test {
    CurveResolverMainnet private resolver;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_600_440);
        vm.selectFork(mainnetFork);

        resolver = new CurveResolverMainnet(ICurveMetaRegistry(0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC));
    }

    function testStableSwapMetaBase() public {
        address[] memory et = new address[](8);

        // 3Pool
        et[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        et[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        et[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        assertPool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, et, 3, 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490, true);
    }

    function testStableSwapPools() public {
        address[] memory et = new address[](8);

        // stetheth
        et[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        et[1] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        assertPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, et, 2, 0x06325440D014e39736583c165C2963BA99fAf14E, true);

        // fraxusdc
        et[0] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        et[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        assertPool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2, et, 2, 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC, true);

        // susd - not actually a meta pool
        et[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        et[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        et[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        et[3] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
        assertPool(0xA5407eAE9Ba41422680e2e00537571bcC53efBfD, et, 4, 0xC25a3A3b969415c80451098fa907EC722572917F, true);

        // frxeth
        et[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        et[1] = 0x5E8422345238F34275888049021821E8E08CAa1f;
        assertPool(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577, et, 2, 0xf43211935C781D5ca1a41d2041F397B8A7366C7A, true);

        // tusd
        et[0] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        et[1] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3pool bp
        assertPool(0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1, et, 2, 0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1, true);

        // hbtc
        et[0] = 0x0316EB71485b0Ab14103307bf65a021042c6d380;
        et[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        assertPool(0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F, et, 2, 0xb19059ebb43466C323583928285a49f558E572Fd, true);

        // Paxos Dollar (USDP)
        et[0] = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
        et[1] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3pool bp
        assertPool(0xc270b3B858c335B6BA5D5b10e2Da8a09976005ad, et, 2, 0xc270b3B858c335B6BA5D5b10e2Da8a09976005ad, true);
    }

    function testStableSwapFactoryPools() public {
        address[] memory et = new address[](8);

        // crvUSD/USDC
        et[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        et[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        assertPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E, et, 2, 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E, true);

        // crvUSD/USDT
        et[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        et[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        assertPool(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4, et, 2, 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4, true);

        // crvUSD/TUSD
        et[0] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        et[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        assertPool(0x34D655069F4cAc1547E4C8cA284FfFF5ad4A8db0, et, 2, 0x34D655069F4cAc1547E4C8cA284FfFF5ad4A8db0, true);

        // stETH concentrated
        et[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        et[1] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        assertPool(0x828b154032950C8ff7CF8085D841723Db2696056, et, 2, 0x828b154032950C8ff7CF8085D841723Db2696056, true);

        // TUSDFRAXBP
        et[0] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        et[1] = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // frax/usdc bp
        assertPool(0x33baeDa08b8afACc4d3d07cf31d49FC1F1f3E893, et, 2, 0x33baeDa08b8afACc4d3d07cf31d49FC1F1f3E893, true);

        // agEUR/EUROC
        et[0] = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;
        et[1] = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
        assertPool(0xBa3436Fd341F2C8A928452Db3C5A3670d1d5Cc73, et, 2, 0xBa3436Fd341F2C8A928452Db3C5A3670d1d5Cc73, true);

        // 3CRV/lvUSD
        et[0] = 0x94A18d9FE00bab617fAD8B49b11e9F1f64Db6b36;
        et[1] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3pool bp
        assertPool(0xe9123CBC5d1EA65301D417193c40A72Ac8D53501, et, 2, 0xe9123CBC5d1EA65301D417193c40A72Ac8D53501, true);
    }

    function testCryptoPools() public {
        address[] memory et = new address[](8);
        bool f = false;

        // tricrypto2
        et[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        et[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        et[2] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // UI shows 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        assertPool(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, et, 3, 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff, f);

        // crveth
        et[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        et[1] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        assertPool(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, et, 2, 0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d, f);
    }

    function testCryptoFactoryPools() public {
        address[] memory et = new address[](8);
        bool f = false;

        // ldo/eth
        et[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        et[1] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        assertPool(0x9409280DC1e6D33AB7A8C6EC03e5763FB61772B5, et, 2, 0xb79565c01b7Ae53618d9B847b9443aAf4f9011e7, f);

        // eUSD/USDC
        et[0] = 0x97de57eC338AB5d51557DA3434828C5DbFaDA371;
        et[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        assertPool(0x880F2fB3704f1875361DE6ee59629c6c6497a5E3, et, 2, 0xb2C35aC676F4A002669e195CF4dc50DDeDF6F0fA, f);

        // Rocketpool rETH/ETH
        et[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        et[1] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        assertPool(0x0f3159811670c117c372428D4E69AC32325e4D0F, et, 2, 0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C, f);

        // DCHF/3CRV
        // Is a crypto, non pegged pool, but uses 3Crv
        et[0] = 0x045da4bFe02B320f4403674B3b7d121737727A36;
        et[1] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; //3pool bp
        assertPool(0xDcb11E81C8B8a1e06BF4b50d4F6f3bb31f7478C3, et, 2, 0x8Bc3F1e82Ca3d63987dc12F90538c6bF818FcD0f, f);

        // CVX/FraxBP
        // Is a crypto, non pegged pool, but uses FRAX/USDC
        et[0] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        et[1] = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; //frax/usdc bp
        assertPool(0xBEc570d92AFB7fFc553bdD9d4B4638121000b10D, et, 2, 0x7F17A6C77C3938D235b014818092eb6305BdA110, f);
    }

    function test_getReservesInfo_ReturnsData() public view {
        resolver.getReservesInfo(0x21E27a5E5513D6e65C4f830167390997aA84843a);
    }

    function assertPool(
        address pool,
        address[] memory expectedTokens,
        uint256 expectedNumTokens,
        address expectedLP,
        bool expectedIsStableSwap
    ) internal {
        (address[8] memory tokens, uint256 numTokens, bool isStableSwap) = resolver.resolve(pool);
        (address[8] memory wlpTokens, uint256 wlNumTokens, address lpToken, bool wlpIsStableSwap) =
            resolver.resolveWithLpToken(pool);

        for (uint256 i = 0; i < 8; i++) {
            assertEq(tokens[i], expectedTokens[i], "token");
            assertEq(wlpTokens[i], expectedTokens[i], "token");
            expectedTokens[i] = address(0); // Reset
        }

        assertEq(expectedNumTokens, numTokens, "numTokens");
        assertEq(expectedNumTokens, wlNumTokens, "wlNumTokens");
        assertEq(expectedIsStableSwap, isStableSwap, "isStableSwap");
        assertEq(expectedIsStableSwap, wlpIsStableSwap, "wlpIsStableSwap");
        assertEq(expectedLP, lpToken, "lpToken");
    }
}
