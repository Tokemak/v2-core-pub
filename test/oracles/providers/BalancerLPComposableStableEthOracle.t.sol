// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IVault as IBalancerVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerLPComposableStableEthOracle } from "src/oracles/providers/BalancerLPComposableStableEthOracle.sol";
import {
    BAL_VAULT,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SFRXETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL,
    CBETH_MAINNET,
    UNI_ETH_MAINNET,
    WETH_MAINNET,
    DAI_MAINNET,
    USDC_MAINNET,
    UNI_WETH_POOL,
    USDT_MAINNET,
    CBETH_WSTETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerLPComposableStableEthOracleTests is Test {
    IBalancerVault private constant VAULT = IBalancerVault(BAL_VAULT);
    address private constant WSTETH = address(WSTETH_MAINNET);
    address private constant RETH = address(RETH_MAINNET);
    address private constant SFRXETH = address(SFRXETH_MAINNET);
    address private constant WSTETH_RETH_SFRXETH_POOL = address(WSETH_RETH_SFRXETH_BAL_POOL);
    address private constant UNIETH = address(UNI_ETH_MAINNET);
    address private constant WETH = address(WETH_MAINNET);
    address private constant UNIETH_WETH_POOL = address(UNI_WETH_POOL);

    IRootPriceOracle private rootPriceOracle;
    ISystemRegistry private systemRegistry;
    BalancerLPComposableStableEthOracle private oracle;

    uint256 private mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_378_951);
        vm.selectFork(mainnetFork);

        rootPriceOracle = IRootPriceOracle(vm.addr(324));
        systemRegistry = generateSystemRegistry(address(rootPriceOracle));
        oracle = new BalancerLPComposableStableEthOracle(systemRegistry, VAULT);
    }

    function testConstruction() public {
        assertEq(address(systemRegistry), address(oracle.getSystemRegistry()));
        assertEq(address(VAULT), address(oracle.balancerVault()));
    }

    function testWstETHsFRXEthrETHPool() public {
        mockRootPrice(WSTETH, 1_124_023_737_293_252_681); //wstETH
        mockRootPrice(RETH, 1_071_929_592_001_012_800); //rETH
        mockRootPrice(SFRXETH, 1_039_355_991_640_087_568); //sfrxETH

        uint256 price = oracle.getPriceInEth(WSTETH_RETH_SFRXETH_POOL);

        assertEq(price > 99e16, true);
        assertEq(price < 11e17, true);
    }

    function testUsdBasedPool() public {
        mockRootPrice(USDC_MAINNET, 535_370_000_000_000); //USDC
        mockRootPrice(DAI_MAINNET, 534_820_000_000_000); //DAI
        mockRootPrice(USDT_MAINNET, 535_540_000_000_000); //USDT

        // //solhint-disable-next-line max-line-length
        // https://app.balancer.fi/#/ethereum/pool/0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7
        // Pool Value at the time: $4,349,961
        // Actual Supply: 4351658.079624087001833240
        // Eth Price: $1,868.05
        uint256 price = oracle.getPriceInEth(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);

        assertApproxEqAbs(price, 535_109_000_000_000, 10_000_000_000_000);
    }

    function testLowestIndividualTokenPriceTokenLowersOverall() public {
        mockRootPrice(WSTETH, 1e17); //wstETH
        mockRootPrice(RETH, 1_071_929_592_001_012_800); //rETH
        mockRootPrice(SFRXETH, 1_039_355_991_640_087_568); //sfrxETH

        uint256 price = oracle.getPriceInEth(WSTETH_RETH_SFRXETH_POOL);

        assertEq(price < 90e16, true);
    }

    function testReentrancyGuard() public {
        mockRootPrice(UNIETH, 1_024_023_737_293_252_681); //uniETH
        mockRootPrice(WETH, 1_024_023_737_293_252_681); //WETH

        // Runs a getPriceEth inside of a vault operation
        ReentrancyTester tester = new ReentrancyTester(oracle, address(VAULT), UNIETH, UNIETH_WETH_POOL);
        deal(UNIETH, address(tester), 10e18);
        deal(address(tester), 10e18);
        tester.run();

        assertEq(tester.getPriceFailed(), true);
        assertEq(tester.priceReceived(), type(uint256).max);
    }

    function testMissingTokensReverts() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");
        vm.mockCall(
            mockPool, abi.encodeWithSelector(IBalancerComposableStablePool.getPoolId.selector), abi.encode(badPoolId)
        );
        //solhint-disable-next-line max-line-length
        vm.mockCall(mockPool, abi.encodeWithSelector(IBalancerComposableStablePool.getBptIndex.selector), abi.encode(0));

        address mockVault = vm.addr(3_434_343);

        ISystemRegistry localSystemRegistry = generateSystemRegistry(address(rootPriceOracle));
        BalancerLPComposableStableEthOracle localOracle =
            new BalancerLPComposableStableEthOracle(localSystemRegistry, IBalancerVault(mockVault));

        IERC20[] memory tokens = new IERC20[](0);
        uint256[] memory amounts = new uint256[](0);
        uint256 lastChangeBlock = block.number;
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IBalancerVault.getPoolTokens.selector),
            abi.encode(tokens, amounts, lastChangeBlock)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BalancerLPComposableStableEthOracle.InvalidPrice.selector, mockPool, type(uint256).max
            )
        );
        localOracle.getPriceInEth(mockPool);
    }

    function testInvalidPoolIdReverts() public {
        address mockPool = vm.addr(3434);
        bytes32 badPoolId = keccak256("x2349382440328");
        vm.mockCall(
            mockPool, abi.encodeWithSelector(IBalancerComposableStablePool.getPoolId.selector), abi.encode(badPoolId)
        );

        vm.expectRevert("BAL#500");
        oracle.getPriceInEth(mockPool);
    }

    function testEnsureBptTokenNotPricedIn() public {
        mockRootPrice(WSTETH, 1_124_023_737_293_252_681); //wstETH
        mockRootPrice(RETH, 1_071_929_592_001_012_800); //rETH
        mockRootPrice(SFRXETH, 1_039_355_991_640_087_568); //sfrxETH
        mockRootPrice(WSTETH_RETH_SFRXETH_POOL, 10_000_039_355_991_640_087_568); //sfrxETH

        uint256 price = oracle.getPriceInEth(WSTETH_RETH_SFRXETH_POOL);

        assertEq(price > 99e16, true);
        assertEq(price < 11e17, true);
    }

    function mockRootPrice(address token, uint256 price) internal {
        vm.mockCall(
            address(rootPriceOracle),
            abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector, token),
            abi.encode(price)
        );
    }

    function generateSystemRegistry(address rootOracle) internal returns (ISystemRegistry) {
        address registry = vm.addr(327_849);
        vm.mockCall(registry, abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector), abi.encode(rootOracle));
        return ISystemRegistry(registry);
    }
}

contract ReentrancyTester {
    BalancerLPComposableStableEthOracle private oracle;
    address private balancerVault;
    address private nonWethToken;
    address private poolAddress;

    uint256 public priceReceived = type(uint256).max;
    bool public getPriceFailed = false;

    // Same as defined in BalancerUtilities
    error BalancerVaultReentrancy();

    constructor(
        BalancerLPComposableStableEthOracle _oracle,
        address _balancerVault,
        address _nonWethToken,
        address _poolAddress
    ) {
        oracle = _oracle;
        balancerVault = _balancerVault;
        nonWethToken = _nonWethToken;
        poolAddress = _poolAddress;

        IERC20(nonWethToken).approve(balancerVault, type(uint256).max);
    }

    function run() external {
        address[] memory assets = new address[](3);
        assets[0] = poolAddress;
        assets[1] = address(0);
        assets[2] = address(nonWethToken);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 5e17 - 1e9;
        amounts[2] = 48_560_623_982_835_670;

        uint256[] memory amountsUser = new uint256[](2);
        amountsUser[0] = 5e17 - 1e9;
        amountsUser[1] = 48_560_623_982_835_670;

        uint256 msgValue;
        msgValue = 5e17;

        // wstETH/WETH
        IBalancerVault(balancerVault).joinPool{ value: msgValue }(
            0xbfce47224b4a938865e3e2727dc34e0faa5b1d82000000000000000000000527, //UNIETH-WETH
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                amounts,
                abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsUser, 0),
                false // Don't use internal balances
            )
        );
    }

    receive() external payable {
        if (msg.sender == balancerVault) {
            try oracle.getPriceInEth(address(WSETH_RETH_SFRXETH_BAL_POOL)) returns (uint256 price) {
                priceReceived = price;
            } catch (bytes memory err) {
                if (keccak256(abi.encodeWithSelector(BalancerVaultReentrancy.selector)) == keccak256(err)) {
                    getPriceFailed = true;
                }
            }
        }
    }
}
