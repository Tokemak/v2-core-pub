// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { TestWETH9 } from "test/mocks/TestWETH9.sol";
import { Pausable } from "src/security/Pausable.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { BASE_SEQUENCER_FEED } from "test/utils/Addresses.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { SequencerChecker } from "src/security/SequencerChecker.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemSecurityL2 } from "src/security/SystemSecurityL2.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";

// solhint-disable func-name-mixedcase

contract SystemSecurityL2IntegrationTest is Test {
    uint256 public constant MINT_AMOUNT = 1e18;
    uint256 public constant MIN_STAKING_DURATION = 30 days;

    SystemRegistry public systemRegistry;
    AccessController public accessController;

    AutopoolETH public autopool;

    SystemSecurityL2 public systemSecurity;
    SequencerChecker public checker;

    MockERC20 public toke;
    TestWETH9 public weth;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 15_064_413);

        // Set up toke
        toke = new MockERC20("Toke", "Toke", 18);
        toke.mint(address(this), MINT_AMOUNT);

        // Set up weth
        weth = new TestWETH9();
        weth.mint(address(this), MINT_AMOUNT);

        // Set up registry
        systemRegistry = new SystemRegistry(address(toke), address(weth));
        systemRegistry.addRewardToken(address(weth));
        systemRegistry.addRewardToken(address(toke));

        // Set up Access
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));

        // Set up security
        systemSecurity = new SystemSecurityL2(systemRegistry);
        systemRegistry.setSystemSecurity(address(systemSecurity));

        // Set up checker
        checker = new SequencerChecker(systemRegistry, IAggregatorV3Interface(BASE_SEQUENCER_FEED));
        systemRegistry.setSequencerChecker(address(checker));

        // Deploy autopool
        address autopoolStrategy = makeAddr("autopoolStrategy");
        address template = address(new AutopoolETH(systemRegistry, address(weth)));
        autopool = AutopoolETH(Clones.cloneDeterministic(template, keccak256("1")));
        weth.mint(address(this), 100_000);
        weth.approve(address(autopool), 100_000);
        autopool.initialize(autopoolStrategy, "1", "1", abi.encode(""));

        // Deposit weth to autopool
        weth.approve(address(autopool), MINT_AMOUNT);
        autopool.deposit(MINT_AMOUNT, address(this));
    }

    function test_RevertIf_FullSystemPause() public {
        accessController.setupRole(Roles.EMERGENCY_PAUSER, address(this));
        systemSecurity.pauseSystem();

        assertEq(systemSecurity.isSystemPaused(), true);

        vm.expectRevert(Pausable.IsPaused.selector);
        autopool.withdraw(1e18, address(this), address(this));
    }

    function test_RevertIf_PauseDueToSequencerDowntime() public {
        _mockFeedReturn(1); // Return false to SequencerChecker.sol contract

        assertEq(checker.checkSequencerUptimeFeed(), false);
        assertEq(systemSecurity.isSystemPaused(), true);

        vm.expectRevert(Pausable.IsPaused.selector);
        autopool.withdraw(1e18, address(this), address(this));
    }

    function test_WorksWhenNotPaused() public {
        assertEq(checker.checkSequencerUptimeFeed(), true);
        assertEq(systemSecurity.isSystemPaused(), false);

        autopool.withdraw(1e18, address(this), address(this));

        assertEq(weth.balanceOf(address(autopool)), 100_000);
        assertEq(weth.balanceOf(address(this)), MINT_AMOUNT);
    }

    // Have to mock what feed is returning if we want false returned
    function _mockFeedReturn(int256 answer) private {
        vm.mockCall(
            BASE_SEQUENCER_FEED,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, answer, 1, 1, 1)
        );
    }
}
